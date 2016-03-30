
$ = require 'bling'
Process = require "../process"
Shell = require 'shelljs'
Fs = require 'fs'
{configFile} = require "./files"
{echo, stdout, stderr} = require "./output"
codec = $.TNET
echo = $.logger "[shepd]"

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
		@cooldown = 25 # this increases after each failed restart
		# is this process expected to be running?
		@expected = false
		# expose uptime
		$.defineProperty @, 'uptime', {
			get: => if @started then ($.now - started) else 0
		}
		@log = $.logger "[shepd] [#{@id}]"

	# Start this process if it isn't already.
	start: ->
		if @started
			echo "Ignoring request to start instance #{@id} (reason: already started)."
			return
		@expected = true
		env = {}
		if @port
			Process.findOne({ ports: [ @port ] }).then (proc) =>
				if proc
					Process.kill proc.pid, 'SIGTERM'
				if @port
					env.PORT = @port
				@proc = Shell.exec @exec, { cwd: @cd, env: env, silent: true, async: true }
				@started = $.now
				resetCooldown = $.delay 5000, => @cooldown = 25
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
						@cooldown *= 2
						@log "Automatically restarting... (#{(@cooldown / 1000).toFixed 2}s cooldown)"
						resetCooldown.cancel()
						$.delay @cooldown, => @start()
					else
						@proc?.unref?()
						@proc = undefined

	stop: ->
		@expected = false
		unless @started
			echo "Ignoring request to stop instance #{@id} (reason: already stopped)."
			return
		if @proc?.pid
			echo "Killing process: #{@proc.pid}..."
			Shell.exec "kill #{@proc.pid}"
			@started = undefined

	restart: ->
		if @started then @stop()
		@start()
	
	enable: -> @start() # these look identical here, but enable/disable are saved to the config log
	disable: -> @stop() # while stop/start are not


doInstance = (method, instanceId) ->
	return unless instanceId?.length
	[groupId, index] = instanceId.split('-')
	index = parseInt index, 10
	echo "About to #{method} instance #{index} in #{groupId} group."
	# echo Groups[groupId].procs[index]
	Groups[groupId].procs[index][method]()
	null

doGroup = (method, groupId) ->
	return unless groupId?.length and groupId of Groups
	for proc in Groups[groupId].procs
		proc[method]()
	null

doAll = (method) ->
	for group of Groups
		for proc in group.procs
			proc[method]
	null

simple = (method, doLog=false) -> {
	onMessage: (msg) ->
		switch
			when msg.g then doGroup method, msg.g
			when msg.i then doInstance method, msg.i
			else
				doAll method
		doLog
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
