$       = require 'bling'
Shell   = require 'shelljs'
Process = require './process'
Helpers = require './helpers'
module.exports = \
class Server
	constructor: (opts, index) ->
		$.extend @,
			opts: opts
			index: index or 0
			port: opts.port + (index or 0)
			process: null
			started: $.Promise()
		$.extend @started,
			attempts: 0
			timeout: null
		@log = $.logger @toString()

	spawn: ->
		try return @started
		finally
			cmd = ""
			@started.reset()
			@log "Spawning..."
			Process.findOne({ ports: @port }).then (owner) =>
				if owner? # if the port is being listened on
					@log "Killing previous owner of", @port, "PID:", owner.pid
					owner.kill "SIGKILL" # send kill signal that cant be refused
					$.delay @opts.restart.gracePeriod, => @spawn()
				else
					cmd = "#{makeEnvString @} bash -c 'cd #{@opts.cd} && #{@opts.cmd}'"
					@process = Shell.exec cmd, { silent: true, async: true }, $.identity
					@process.on "exit", (err, code) => @onExit code
					on_data = (prefix) => (data) =>
						for line in $(String(data).split /\n/) when line.length
							@log prefix + line
					@process.stdout.on "data", on_data ""
					@process.stderr.on "data", on_data "(stderr) "
					@log "Waiting for port", @port, "to be owned by", @process.pid
					Helpers.portIsOwned(@process.pid, @port, @opts.restart.timeout) \
						.then @started.resolve, @started.reject

	kill: (signal) ->
		try return p = $.Promise()
		finally
			unless @process? then p.reject 'no process'
			else
				@process.on 'exit', p.resolve
				@process.kill signal

	onExit: (exitCode) ->
		return unless @process?
		@log("Server PID: " + @process.pid + " Exited with code: ", exitCode)
		# Record the death of the child
		@process = null
		# if it died with a restartable exit code, attempt to restart it
		if exitCode isnt "SIGKILL" and @started.attempts < @opts.restart.maxAttempts
			@started.attempts += 1
			# schedule the forgetting of start attempts
			clearTimeout @started.timeout
			@started.timeout = setTimeout (=> @started.attempts = 0), @opts.restart.maxInterval
			# attempt a restart
			@spawn()

	toString: -> "[server:"+@port+"]"
	inspect:  -> "[server:"+@port+"]"

	makeEnvString = (self) ->
		ret = ""
		for key,val of self.opts.env when val?
			ret += "#{key}=\"#{val}\" "
		ret += "#{self.opts.portVariable}=\"#{self.port}\""
		return ret

	@defaults = (opts) -> # make sure each server block in the config has the minimum defaults

		opts = $.extend Object.create(null), {
			cd: "."
			cmd: "node index.js"
			count: Math.max(1, Os.cpus().length - 1)
			port: 8000, # a starting port, each child after the first will increment this
			portVariable: "PORT", # and set it in the env using this variable
			poolName: "shepherd_pool"
			env: {}
		}, opts

		opts.port = parseInt opts.port, 10
		opts.count = parseInt opts.count, 10

		while opts.count < 0
			opts.count += Os.cpus().length
		opts.count or= 1

		# control what happens at (re)start time
		opts.restart = $.extend Object.create(null), {
			maxAttempts: 5, # failing five times fast is fatal
			maxInterval: 10000, # in what interval is "fast"?
			gracePeriod: 3000, # how long to wait for a forcibly killed process to die
			timeout: 10000, # how long to wait for a newly launched process to start listening on it's port
		}, opts.restart

		opts.git = $.extend Object.create(null), {
			cd: "."
			remote: "origin"
			branch: "master"
			command: "git pull {{remote}} {{branch}} || git merge --abort"
		}, opts.git

		opts.git.command = Handlebars.compile(opts.git.command)
		opts.git.command.inspect = (level) ->
			return '"' + opts.git.command({ remote: "{{remote}}", branch: "{{branch}}" }) + '"'

		return opts
