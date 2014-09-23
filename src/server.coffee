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
						for line in $(data.split /\n/) when line.length
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
