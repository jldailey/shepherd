
$ = require 'bling'
echo = $.logger "[shepd]"
Shell = require 'shelljs'
codec = $.TNET

# the global herd of processes
Groups = {}

class Group
	constructor: (@name, @cd, @exec, @n, @port) ->
		@procs = $.range(0,@n).map (i) =>
			new Proc "#{@name}-#{i}", @cd, @exec, @port + i, @

class Proc
	constructor: (@id, @cd, @exec, @port, @group) ->
		# the time of the most recent start
		@started = undefined
		# is this process expected to be running?
		@expected = false
		# expose uptime
		$.defineProperty @, 'uptime', {
			get: =>
				return 0 unless @started?
				return $.now - @started
		}
	log: $.logger "[shepd] [#{@id}]"

	# Start this process if it isn't already.
	start: ->
		if @started
			echo "Ignoring request to start instance #{@id} (reason: already started)."
			return
		@expected = true
		@proc = Shell.exec @exec, { cwd: @cd, env: { PORT: @port }, silent: true, async: true }
		@started = $.now
		@proc.stdout.pipe(process.stdout)
		@proc.stderr.pipe(process.stderr)
		@proc.on 'exit', (code, signal) =>
			@log "Process exited, code=#{code} signal=#{signal}."
			@started = undefined
			if @expected
				@log "Automatically restarting..."
				$.immediate => @start()

	stop: ->
		@expected = false
		unless @started
			echo "Ignoring request to stop instance #{@id} (reason: already stopped)."
			return
		@proc.kill('SIGTERM')

	restart: ->



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
		else Groups[msg.g] = new Group(msg.g, msg.cd, msg.exec, msg.n, msg.p)
	remove: TODO 'remove'
	scale: TODO 'scale'
}
