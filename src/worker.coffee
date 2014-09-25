$ = require('bling')
Shell = require('shelljs')
module.exports = \
class Worker
	constructor: (opts, index) ->
		$.extend @,
			opts: opts
			index: index or 0
			process: null
			started: $.extend $.Promise(),
				attempts: 0
				timeout: null
		@log = $.logger("worker[" + this.index + "]")

	spawn: ->
		@started.reset()
		try return @started
		finally
			cmd = "bash -c 'cd #{@opts.cd} && #{@opts.cmd}'"
			@log "shell >", cmd
			@process = Shell.exec cmd, { silent: true, async: true }, $.identity
			@process.on "exit", (err, code) => @onExit(code)
			on_data = (prefix) => (data) =>
				for line in $(String(data).split /\n/) when line.length
					@log prefix + line
			@process.stdout.on "data", on_data ""
			@process.stderr.on "data", on_data "(stderr) "
			@started.resolve @process.pid

	kill: (signal) ->
		try return p = $.Promise()
		finally if @process?
			timeout = setTimeout (=> @process.kill "SIGKILL"), @opts.restart.gracePeriod
			@process.on 'exit', (exitCode) ->
				clearTimeout timeout
				p.resolve(exitCode)
			@process.kill signal
		else p.reject 'no process to kill'

	onExit: (exitCode) -> # Record the death, and maybe attempt to restart it
		return unless @process?
		@log "Worker PID: " + @process.pid + " exited with code: ", exitCode
		@process = null
		# if it died with a restartable exit code, attempt to restart it
		if exitCode isnt "SIGKILL" and @started.attempts < @opts.restart.maxAttempts
			@started.attempts += 1
			clearTimeout @started.timeout # schedule the forgetting of start attempts
			@started.timeout = setTimeout (=> @started.attempts = 0), @opts.restart.maxInterval
			# attempt an automatic restart
			@spawn()

	@defaults = (opts) ->
		opts = $.extend {
			count: 1
			cd: "."
			cmd: "echo 'No worker cmd specified!'"
		}, opts

		opts.count = parseInt opts.count, 10

		while opts.count < 0
			opts.count += Os.cpus().length
		opt.count or= 1

		# control what happens at (re)start time
		opts.restart = $.extend Object.create(null), {
			maxAttempts: 5, # failing five times fast is fatal
			maxInterval: 10000, # in what interval is "fast"?
			gracePeriod: 3000 # how long to wait for a forcibly killed process to die
		}, opts.restart

		return opts


