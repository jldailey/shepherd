
$ = require 'bling'
Process = require "../process"
Shell = require 'shelljs'
Fs = require 'fs'
{configFile} = require "./files"
{echo, stdout, stderr} = Output = require "./output"
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
		@cooldown = 25 # this increases after each failed restart
		# is this process expected to be running?
		@expected = false
		# expose uptime
		$.defineProperty @, 'uptime', {
			get: => if @started then ($.now - @started) else 0
		}
		@log = $.logger "[shepd] [#{@id}]"

	# Start this process if it isn't already.
	start: ->
		if @started
			echo "Ignoring request to start instance #{@id} (reason: already started)."
			return false
		unless @enabled
			echo "Ignoring request to start instance #{@id} (reason: disabled)."
			return false
		@expected = true
		env = {}
		resetCooldown = $.delay 5000, => @cooldown = 25
		retryStart = =>
			@cooldown *= 2
			resetCooldown.cancel()
			$.delay @cooldown, => @start()
		doStart = =>
			@proc = Shell.exec @exec, { cwd: @cd, env: env, silent: true, async: true }
			@started = $.now
			@proc.stdout.on 'data', (data) =>
				for line in data.toString().split '\n'
					stdout.write "[#{@id}] " + line + "\n"
			@proc.stderr.on 'data', (data) =>
				for line in data.toString().split '\n'
					stderr.write "[#{@id}] (stderr) " + line + "\n"
			@proc.on 'exit', (code, signal) =>
				@log "Process exited, code=#{code} signal=#{signal}."
				@started = undefined
				if @expected
					retryStart()
				else
					@proc?.unref?()
					@proc = undefined
		if @port
			env.PORT = @port
			Process.findOne({ ports: @port }).then (proc) =>
				if proc
					@log "Attempting to kill owner of my port, pid:", proc.pid
					Process.kill proc.pid, 'SIGTERM'
					retryStart()
				else doStart()
		else doStart()
		true

	stop: ->
		@expected = false
		unless @started
			echo "Ignoring request to stop instance #{@id} (reason: already stopped)."
		else if @proc?.pid
			echo "Killing process: #{@proc.pid}..."
			Shell.exec "kill #{@proc.pid}"
			@started = undefined
			return true
		false

	restart: ->
		if @started then @stop()
		@start()
	
	enable: ->
		acted = ! @enabled
		@enabled = true
		@start()
		acted
	disable: ->
		acted = @enabled
		@enabled = false
		@stop() # while stop/start are not
		acted


doInstance = (method, instanceId) ->
	acted = false
	return acted unless instanceId?.length
	[groupId, index] = instanceId.split('-')
	index = parseInt index, 10
	echo "About to #{method} instance #{index} in #{groupId} group."
	# echo Groups[groupId].procs[index]
	acted = Groups[groupId].procs[index][method]()
	return acted

doGroup = (method, groupId) ->
	acted = false
	unless groupId?.length and groupId of Groups
		echo "Invalid --group parameter: '#{groupId}'"
		return false
	for proc in Groups[groupId].procs
		acted or= proc[method]()
	return acted

doAll = (method) ->
	acted = false
	for group of Groups
		for proc in group.procs
			acted or= proc[method]
	return acted

simple = (method, doLog=false) -> {
	onMessage: (msg) ->
		acted = switch
			when msg.g then doGroup method, msg.g
			when msg.i then doInstance method, msg.i
			else doAll method
		acted and doLog
}

module.exports = actions = {
	start:   simple 'start', false
	stop:    simple 'stop', false
	restart: simple 'restart', false
	disable: simple 'disable', true
	enable:  simple 'enable', true
	status: {
		onMessage: (msg, client) ->
			output = []
			$.valuesOf(Groups).each (group) ->
				healthy = undefined
				if 'health' of group and 'health' of proc
					healthy = proc.health.status
				for proc in group.procs
					output.push [ proc.id, proc.proc?.pid, proc.port, proc.uptime, healthy ]
			client.write codec.stringify(output)
			return false
	}
	tail: {
		onMessage: (msg, client) ->
			Output.tail(client)
			return false
	}
	add: {
		onMessage: (msg) ->
			unless msg.g and msg.g.length
				echo "--group is required with 'add'"
				return false
			if msg.g of Groups
				echo "Ignoring add request for group #{msg.g} (reason: already created)."
				return false
			else
				Groups[msg.g] = new Group(msg.g, msg.cd, msg.exec, msg.n, msg.p)
				return true
	}
	remove: {
		onMessage: (msg) ->
			unless msg.g and msg.g.length and msg.g of Groups
				echo "Ignoring request to remove group: '#{msg.g}'."
				return false
			else
				delete Groups[msg.g]
				return true
	}
	scale: {
		onMessage: (msg) ->
			unless msg.g and msg.g.length
				echo "--group is required with 'scale'"
				return false
			unless msg.g of Groups
				echo "Unknown group name passed to --group ('#{msg.g}')"
				return false
			group = Groups[msg.g]
			dn = group.n - msg.n
			if dn is 0
				echo "Ignoring request to scale to the same n (#{msg.n})"
				return false
			else if dn > 0
				echo "Adding #{dn} instances..."
			else if dn < 0
				echo "Scaling back #{dn} instances..."
			return true
	}
}
