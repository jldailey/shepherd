
$ = require 'bling'
Shell = require 'shelljs'
Process = require '../util/process'
echo = $.logger "[groups]"
warn = $.logger "[warning]"

# the global herd of processes
Groups = new Map()
# m.clear m.delete m.entries m.forEach m.get m.has m.keys m.set m.size m.values

class Group
	createProcess = (g, i) ->
		port = undefined
		if g.port
			port = g.port + i
		new Proc "#{g.name}-#{i}", g.cd, g.exec, port, g
	constructor: (@name, @cd, @exec, @n, @port) ->
		@procs = $.range(0,@n).map (i) => createProcess @, i
	scale: (n) ->
		dn = n - @n
		if dn > 0
			echo "Adding #{dn} instances..."
			for d in [0...dn] by 1
				@procs.push createProcess(@, @n + d).start()
		else if dn < 0
			echo "Trimming #{dn} instances..."
			while @n < n
				@procs.pop().stop()
				@n += 1
	actOn: (method) ->
		return @procs
			.select(method)
			.call()
			.reduce false, (a, x) -> a or x
	toString: ->
		("[#{proc.id}:#{proc.port}:#{proc.statusString}] " for proc in @procs).join " "

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
		statusString = "disabled"
		$.defineProperty @, 'statusString', {
			get: -> return statusString
			set: (v) =>
				statusString = v
				@log @group.toString()
		}
	
	log: (args...) ->
		$.log "[#{@id}]", args...

	# Start this process if it isn't already.
	start: ->
		if @started
			return false
		unless @enabled
			return false
		@expected = true
		env = { PORT: @port }
		retryStart = =>
			return unless @enabled
			@cooldown = (Math.min 10000, @cooldown * 2)
			@statusString = "waiting #{@cooldown}"
			$.delay @cooldown, =>
				@start()
		doStart = =>
			return unless @enabled
			@statusString = "starting"
			@proc = Shell.exec @exec, { cwd: @cd, env: env, silent: true, async: true }
			if @port
				checkStarted = $.interval 500, =>
					Process.findOne({ ports: @port }).then (proc) =>
						if proc?.pid is @proc.pid # owned by us
							@started = $.now
							@cooldown = 25
							@statusString = "started"
							checkStarted.cancel()
			else # if there is no port to wait for
				# then staying up for 3 (or more) seconds, counts as started
				checkStarted = $.delay (Math.max 3000, @cooldown), =>
					@started = $.now
					@cooldown = 25
					@statusString = "started"
			@proc.stdout.on 'data', (data) => $.log "[#{@id}]", data.toString("utf8")
			@proc.stderr.on 'data', (data) => $.log "[#{@id}] (stderr)", data.toString("utf8")
			@proc.on 'exit', (code, signal) =>
				checkStarted?.cancel()
				@log "Process exit.", {code, signal}
				@statusString = "exit(#{code})"
				@started = undefined
				if @expected then retryStart()
				else
					@proc.unref?()
					@proc = undefined
		if @port
			Process.findOne({ ports: @port }).then (proc) =>
				if proc
					@statusString = "killing #{proc.pid}"
					Process.kill(proc.pid, 'SIGTERM').wait retryStart
				else
					doStart()
		else
			doStart()
		return @

	stop: (cb) ->
		@statusString = "stopping"
		@expected = false
		unless @started
			# warn "Ignoring request to stop instance #{@id} (reason: already stopped)."
		else if @proc?.pid
			Shell.exec "kill #{@proc.pid}", { silent: true, async: true }, -> cb? true
			@started = undefined
			@statusString = "stopped"
			return true
		@statusString = "stopped"
		cb? false
		return false

	restart: ->
		@statusString = "restarting"
		@stop => @start()

	enable: ->
		acted = ! @enabled
		@enabled = true
		@statusString = "enabled"
		if acted then @start()
		acted

	disable: ->
		acted = @enabled
		@enabled = false
		if acted then @stop()
		@statusString = "disabled"
		acted

actOnInstance = (method, instanceId) ->
	return false unless instanceId?.length
	acted = false
	[groupId, index] = instanceId.split('-')
	index = parseInt index, 10
	proc = Groups.get(groupId).procs[index]
	echo "acting on instance", method, instanceId, groupId, index, proc
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
	echo "simpleAction", method, msg
	acted = switch
		when msg.g then Groups.get(msg.g)?.actOn method
		when msg.i then actOnInstance method, msg.i
		else actOnAll method
	acted and doLog

$.extend module.exports, { Groups, actOnAll, actOnInstance, addGroup, removeGroup, simpleAction }
