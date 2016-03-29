
$ = require 'bling'
Shell = require 'shelljs'
Process = require "../process"
{echo, stdout, stderr} = require "./output"
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
		@cooldown = 25 # this increases after each failed restart
		# is this process expected to be running?
		@expected = false
		# expose uptime
		$.defineProperty @, 'uptime', {
			get: =>
				return 0 unless @started?
				return $.now - @started
		}

	log: (args...) -> $.log @id, args...

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
				env.PORT = @port
				@proc = Shell.exec @exec, { cwd: @cd, env: env, silent: true, async: true }
				@started = $.now
				resetCooldown = $.delay 5000, => @cooldown = 0
				@proc.stdout.pipe(stdout)
				@proc.stderr.pipe(stderr)
				@proc.on 'exit', (code, signal) =>
					@log "Process exited, code=#{code} signal=#{signal}."
					@started = undefined
					if @expected
						@cooldown *= 2
						@log "Automatically restarting... (#{(@cooldown / 1000).toFixed 2}s cooldown)"
						resetCooldown.cancel()
						$.delay @cooldown, => @start()

	stop: ->
		@expected = false
		unless @started
			echo "Ignoring request to stop instance #{@id} (reason: already stopped)."
			return
		@proc.kill('SIGTERM')

	restart: ->
		@stop()
		@start()

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

simple = (method) -> (msg) ->
	if msg.g?
		doGroup(method, msg.g)
	else if msg.i?
		doInstance(method, msg.i)
	else
		doAll(method)
	null

TODO = (name) -> -> echo "TODO:", name

module.exports = actions = {
	start: simple 'start'
	stop: simple 'stop'
	restart: simple 'restart'
	status: (msg, client) ->
		output = []
		$.valuesOf(Groups).each (group) ->
			healthy = undefined
			if 'health' of group
				healthy = group.health.status
			for proc in group.procs
				output.push [ proc.id, proc.proc?.pid, proc.port, proc.uptime, healthy ]
		client.write codec.stringify(output)
	add: (msg) ->
		unless msg.g and msg.g.length
			echo "--group is required with 'add'"
			return
		if msg.g of Groups
			echo "Ignoring add request for group #{msg.g} (reason: already created)."
		else
			Groups[msg.g] = new Group(msg.g, msg.cd, msg.exec, msg.n, msg.p)
			Config.saveMessage(msg)
	remove: (msg) ->
		unless msg.g and msg.g.length
			echo "--group is required with 'remove'"
			return
		if msg.g of Groups
			delete Groups[msg.g]
			Config.saveMessage(msg)
	scale: TODO 'scale'
}
