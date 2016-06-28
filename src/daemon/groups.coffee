
$ = require 'bling'
Shell = require 'shelljs'
Process = require '../util/process'
echo = $.logger __filename
warn = $.logger "[warning]"

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
	actOn: (method) ->
		return @procs
			.select(method)
			.call()
			.reduce false, (a, x) -> a or x

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

	# Start this process if it isn't already.
	start: ->
		if @started
			return false
		unless @enabled
			return false
		@expected = true
		env = { PORT: @port }
		# if we don't fail-retry within 5 seconds, revert the cooldown to it's default
		resetCooldown = $.delay 5000, => @cooldown = 150
		retryStart = =>
			@cooldown *= 2 # every time we restart, double the cooldown
			resetCooldown.cancel()
			$.delay @cooldown, => @start()
		doStart = =>
			@proc = Shell.exec @exec, { cwd: @cd, env: env, silent: true, async: true }
			@started = $.now
			@proc.stdout.on 'data', (data) => $.log "[#{@id}]", data.toString("utf8")
			@proc.stderr.on 'data', (data) => $.log "[#{@id}] (stderr)", data.toString("utf8")
			@proc.on 'exit', (code, signal) =>
				echo "Process #{@id} exited, code=#{code} signal=#{signal}."
				@started = undefined
				if @expected then retryStart()
				else
					@proc.unref?()
					@proc = undefined
		if @port
			Process.findOne({ ports: @port }).then (proc) =>
				if proc
					echo "Process #{@id} attempting to kill owner of port #{@port} (pid:", proc.pid,")"
					Process.kill(proc.pid, 'SIGTERM').then retryStart
				else doStart()
		else doStart()
		return true

	stop: (cb) ->
		@expected = false
		unless @started
			# warn "Ignoring request to stop instance #{@id} (reason: already stopped)."
		else if @proc?.pid
			echo "Killing process: #{@proc.pid}..."
			Shell.exec "kill #{@proc.pid}", { silent: true, async: true }, -> cb? true
			@started = undefined
			return true
		cb? false
		return false

	restart: ->
		@stop => @start()

	enable: ->
		acted = ! @enabled
		@enabled = true
		@start()
		acted

	disable: ->
		acted = @enabled
		@enabled = false
		@stop()
		acted

actOnInstance = (method, instanceId) ->
	return false unless instanceId?.length
	acted = false
	[groupId, index] = instanceId.split('-')
	index = parseInt index, 10
	proc = Groups.get(groupId).procs[index]
	return acted = proc[method]()

actOnAll = (method) ->
	acted = false
	Groups.forEach (group) ->
		for proc in group.procs
			acted = proc[method]() or acted
	return acted

addGroup = (name, cd, exec, count, port) ->
	return false if Groups.has(name)
	Groups.set name, new Group(name, cd, exec, count, port)
	return true

removeGroup = (name) ->
	return false unless Groups.has(name)
	Groups.delete name
	return true

simpleAction = (method, doLog=false) -> (msg, client) ->
	$.log "simpleAction", method, msg
	acted = switch
		when msg.g then Groups.get(msg.g)?.actOn method
		when msg.i then actOnInstance method, msg.i
		else actOnAll method
	acted and doLog

$.extend module.exports, { Groups, actOnAll, actOnInstance, addGroup, removeGroup, simpleAction }
