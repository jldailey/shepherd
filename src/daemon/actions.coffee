
$ = require 'bling'
Process = require "../process"
Shell = require 'shelljs'
Fs = require 'fs'
{configFile} = require "./files"
{echo, warn} = Output = require "./output"
codec = $.TNET

# the global herd of processes
Groups = new Map()
# m.clear m.delete m.entries m.forEach m.get m.has m.keys m.set m.size m.values

class Group
	constructor: (@name, @cd, @exec, @n, @port) ->
		@procs = $.range(0,@n).map (i) =>
			port = undefined
			if @port
				port = @port + i
			new Proc "#{@name}-#{i}", @cd, @exec, port, @

class Proc
	constructor: (@id, @cd, @exec, @port, @group) ->
		# the time of the most recent start
		@started = undefined
		@enabled = false
		@cooldown = 150 # this increases after each failed restart
		# is this process expected to be running?
		@expected = false
		# expose uptime
		$.defineProperty @, 'uptime', {
			get: => if @started then ($.now - @started) else 0
		}
		@log = $.logger "[#{@id}]"

	# Start this process if it isn't already.
	start: (cb) ->
		if @started
			# echo "Ignoring request to start instance #{@id} (reason: already started)."
			cb(false)
			return false
		unless @enabled
			# echo "Ignoring request to start instance #{@id} (reason: disabled)."
			cb(false)
			return false
		@expected = true
		env = { PORT: @port }
		# if we don't retry again within 5 seconds, revert the cooldown to it's default
		resetCooldown = $.delay 5000, => @cooldown = 150
		retryStart = =>
			# every time we restart, double the cooldown
			@cooldown *= 2
			resetCooldown.cancel()
			$.delay @cooldown, => @start(cb)
		newlineWrapper = (w) => (data) =>
			lines = data.toString("utf8")
			prefix = "[#{@id}] "
			lines = prefix + lines.replace(/\n$/,'').replace(/\n/g, '\n' + prefix)
			w.write lines
		doStart = =>
			@proc = Shell.exec @exec, { cwd: @cd, env: env, silent: true, async: true }, -> cb(true)
			@started = $.now
			@proc.stdout.on 'data', newlineWrapper Output.stdout
			@proc.stderr.on 'data', newlineWrapper Output.stderr
			@proc.on 'exit', (code, signal) =>
				@log "Process exited, code=#{code} signal=#{signal}."
				@started = undefined
				if @expected
					retryStart()
				else
					@proc?.unref?()
					@proc = undefined
		if @port
			Process.findOne({ ports: @port }).then (proc) =>
				if proc
					@log "Attempting to kill owner of my port, pid:", proc.pid
					Process.kill proc.pid, 'SIGTERM'
					retryStart()
				else doStart()
		else doStart()
		return true

	stop: (cb) ->
		@expected = false
		unless @started
			warn "Ignoring request to stop instance #{@id} (reason: already stopped)."
		else if @proc?.pid
			echo "Killing process: #{@proc.pid}..."
			Shell.exec "kill #{@proc.pid}", { silent: true, async: true }, -> cb(true)
			@started = undefined
			return true
		cb(false)
		return false

	restart: (cb) ->
		@stop ->
			@start cb

	enable: (cb) ->
		acted = ! @enabled
		@enabled = true
		@start(cb)
		acted

	disable: (cb) ->
		acted = @enabled
		@enabled = false
		@stop(cb)
		acted

doInstance = (method, instanceId) ->
	return false unless instanceId?.length
	acted = false
	[groupId, index] = instanceId.split('-')
	index = parseInt index, 10
	proc = Groups[groupId].procs[index]
	return acted = proc[method](cb)

doGroup = (method, groupId, cb) ->
	unless groupId?.length and groupId of Groups
		warn "Invalid --group parameter: '#{groupId}'"
		return false
	acted = false
	n = 1
	done = $.Progress(1)
	for proc in Groups[groupId].procs
		done.progress(null, ++n)
		acted = proc[method](-> done.finish 1) or acted
	done.finish 1
	done.then -> cb(acted)
	return acted

doAll = (method, cb) ->
	acted = false
	n = 1
	done = $.Progress(1) # we start with one initial task: setup
	for k,group of Groups
		for proc in group.procs
			done.progress(null, ++n) # add more work to finish
			echo "[shepd] doAll:", method
			acted = proc[method](-> done.finish 1) or acted
	done.finish 1 # we get credit for setup
	done.then -> cb()
	return acted

simple = (method, doLog=false) -> {
	onMessage: (msg, client) ->
		done = ->
			if client and acted
				client.write codec.stringify getStatus()
		acted = switch
			when msg.g then doGroup method, msg.g, done
			when msg.i then doInstance method, msg.i, done
			else doAll method, done
		acted and doLog
}

getStatus = ->
	output = {
		procs: []
		outputs: Output.getOutputUrls()
	}
	$.valuesOf(Groups).each (group) ->
		for proc in group.procs
			output.procs.push [ proc.id, proc.proc?.pid, proc.port, proc.uptime, proc.healthy ]
	return output

sendStatus = (client) ->
	client?.write codec.stringify getStatus()

module.exports = actions = {
	start:   simple 'start', false
	stop:    simple 'stop', false
	restart: simple 'restart', false
	disable: simple 'disable', true
	enable:  simple 'enable', true
	status: {
		onMessage: (msg, client) ->
			client.write codec.stringify getStatus()
			return false
	}
	tail: {
		onMessage: (msg, client) ->
			Output.tail(client)
			return false
	}
	add: {
		onMessage: (msg, client) ->
			unless msg.g and msg.g.length
				warn "--group is required with 'add'"
				sendStatus(client)
				return false
			if msg.g of Groups
				sendStatus(client)
				return false
			Groups[msg.g] = new Group(msg.g, msg.d, msg.x, msg.n, msg.p)
			sendStatus(client)
			return true
	}
	remove: {
		onMessage: (msg, client) ->
			unless msg.g and msg.g.length and msg.g of Groups
				# warn "Ignoring request to remove group: '#{msg.g}'."
				sendStatus(client)
				return false
			else
				delete Groups[msg.g]
				sendStatus(client)
				return true
	}
	scale: {
		onMessage: (msg, client) ->
			unless msg.g and msg.g.length
				warn "--group is required with 'scale'"
				sendStatus client
				return false
			unless msg.g of Groups
				warn "Unknown group name passed to --group ('#{msg.g}')"
				sendStatus client
				return false
			group = Groups[msg.g]
			dn = group.n - msg.n
			if dn is 0
				# echo "Ignoring request to scale to the same n (#{msg.n})"
				sendStatus client
				return false
			else if dn > 0
				echo "Adding #{dn} instances..."
			else if dn < 0
				echo "Scaling back #{dn} instances..."
			sendStatus client
			return true
	}
	log: {
		onMessage: (msg) ->
			return Output.setOutput msg.u, msg.t, msg.r
	}
	health: {
		onMessage: (msg) -> return switch
			when msg.d then Health.unmonitor msg.u
			when msg.z then Health.pause msg.u
			when msg.r then Health.resume msg.u
			else
				return false unless msg.g of Groups
				Health.monitor Groups[msg.g], msg.p, msg.i, msg.s, msg.t, msg.o
	}
	nginx: {
		onMessage: (msg) ->
	}
}
