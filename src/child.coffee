$       = require 'bling'
Os      = require "os"
Shell   = require 'shelljs'
Handlebars = require "handlebars"
Health  = require './health'
Process = require './process'
Helpers = require './helpers'
Http    = require './http'
Opts    = require './opts'
log = $.logger "[child]"
verbose = ->
	try if Opts.verbose then log.apply null, arguments
	catch err then log "verbose error:", $.debugStack err

class Child
	constructor: (opts, index) ->
		$.extend @,
			opts: opts
			index: index
			process: null
			started: $.extend $.Promise(),
				attempts: 0
				timeout: null
		@log = $.logger @toString()
		@log.verbose = =>
			try if Opts.verbose then @log.apply null, arguments
			catch err then @log "verbose error:", $.debugStack err
		@started.then =>
			@last_start = $.now

	uptime: ->
		return if @last_start then $.now - @last_start else 0
	uptimeString: ->
		$( hours = @uptime() / 3600000,
			 minutes = (hours % 1) * 60,
			 seconds = (minutes % 1) * 60
		)
		.map(-> $.padLeft String(Math.floor @), 2, "0")
		.join(":")

	start: ->
		try return @started
		finally
			fail = (msg) => @started.reject msg
			if ++@started.attempts > @opts.restart.maxAttempts
				fail "too many attempts"
			else
				clearTimeout @started.timeout
				@started.timeout = setTimeout (=> @started.attempts = 0), @opts.restart.maxInterval
				log "shell >" , cmd = "env #{@env()} bash -c 'cd #{@opts.cd} && #{@opts.command}'"
				@process = Shell.exec cmd, { silent: true, async: true }, $.identity
				@process.on "exit", (err, signal) => @onExit err, signal
				on_data = (prefix = "") => (data) =>
					for line in String(data).split /\n/ when line.length
						@log prefix + line
				@process.stdout.on "data", on_data ""
				@process.stderr.on "data", on_data "(stderr) "
				unless @process.pid then fail "no pid"
				# IMPORTANT NOTE: does not resolve @started on it's own,
				# a sub-class like Server or Worker is expected to @started.resolve()

	stop: (signal) ->
		try return p = $.Promise()
		finally
			@started.attempts = Infinity
			@expectedExit = true
			if @process
				try Process.killTree(@process.pid, signal).then p.resolve, p.reject
				catch err
					log "Error calling killTree:", $.debugStack err
			else p.resolve()

	restart: ->
		try return p = $.Promise().then => @last_start = $.now
		finally unless @process?
			log "Starting fresh child (no existing process)"
			@start().then p.resolve, p.reject
		else
			restart = =>
				try
					log "Restarting child..."
					@process = null
					if @port_poller?
						@port_poller.cancel()
					@started.reset()
					@started.attempts = 0
					@start().then p.resolve, p.reject
				catch err
					log "restart error:", $.debugStack err
					p.reject err
			log "Killing existing process", @process.pid
			@expectedExit = true
			Process.killTree(@process.pid, "SIGTERM").wait @opts.restart.gracePeriod, (err) =>
				try
					if String(err) is "Error: timeout"
						log "Child failed to die within #{@opts.restart.gracePeriod}ms, using SIGKILL"
						Process.killTree(@process.pid, "SIGKILL")
							.then restart, p.reject
					else if err then p.reject err
					else restart()
				catch err
					log "restart error during kill tree:", $.debugStack err
					p.reject err

	onExit: (code, signal) ->
		try
			signal = if $.is 'number', code then code - 128 else Process.getSignalNumber signal
			@log "Child exited (signal=#{signal})", if @expectedExit then "(expected)" else ""
			@restart() unless @expectedExit
			@expectedExit = false
		catch err
			@log "child.onExit error:", $.debugStack err

	toString: toString = ->
		try return "#{@constructor.name}[#{@index}]"
		catch err then log "toString error:", $.debugStack err
	inspect:  toString

	env: ->
		try return ("#{key}=\"#{val}\"" for key,val of @opts.env when val?).join " "
		catch err then log "env error:", $.debugStack err

	Child.defaults = (opts) ->
		opts = $.extend Object.create(null), {
			cd: "."
			command: "node index.js"
			count: -1
			env: {}
		}, opts

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

		# defaults for the git configuration
		opts.git = $.extend Object.create(null), {
			enabled: false
			cd: "."
			remote: "origin"
			branch: "master"
			command: "git pull {{remote}} {{branch}} || git merge --abort"
		}, opts.git
		opts.git.command = Handlebars.compile(opts.git.command)
		opts.git.command.inspect = (level) ->
			return '"' + opts.git.command({ remote: "{{remote}}", branch: "{{branch}}" }) + '"'

		return opts

class Worker extends Child
	Http.get "/workers", (req, res) ->
		res.pass """[#{
			("[#{worker.process?.pid ? "DEAD"}, #{worker.port}]" for worker in workers).join ",\n"
		}]"""
	Http.get "/workers/restart", (req, res) ->
		for worker in workers
			worker.restart()
		res.redirect 302, "/console#restarting-workers"
	workers = []

	constructor: (opts, index) ->
		Child.apply @, [
			opts = Worker.defaults(opts),
			index
		]
		workers.push @
		@log = if opts.prefix
			$.logger "#{@opts.prefix}[#{@index}]"
		else
			$.logger @toString()

	start: ->
		super()
		@started.resolve()

	Worker.defaults = Child.defaults

class Server extends Child
	Http.get "/servers", (req, res) ->
		ret = "["
		for port,v of servers
			ret += ("[#{s.process?.pid ? "DEAD"}, #{s.port}]" for s in v).join ",\n"
		res.pass ret + "]"
	Http.get "/servers/restart", (req, res) ->
		$.valuesOf(servers).flatten().select('restart').call()
		res.redirect 302, "/console#restarting-servers"

	# a map of base port to all Server instances based on that port
	servers = {}

	constructor: (opts, index) ->
		Child.apply @, [
			opts = Server.defaults(opts),
			index
		]
		@port = opts.port + index
		@log = $.logger "(#{@opts.prefix or @opts.cd}:#{@port})"
		(servers[opts.port] ?= []).push @

	# wrap the default start function
	start: ->
		@started.then =>
			Health.monitor @port, @process.pid, @opts.check
		try return @started
		finally
			# find any process that is listening on our port
			Process.clearCache().findOne({ ports: @port }).then (owner) =>
				if owner? # if the port is being listened on
					@log "Killing previous owner of", @port, "PID:", owner.pid
					Process.killTree(owner, "SIGKILL").then =>
						@start()
				else # port is available, so really start
					super() # do the base Child start
					unless @process then @started.reject("no process")
					else
						verbose "Waiting for port", @port, "to be owned by", @process.pid
						if @port_poller?
							@port_poller.cancel()
						@port_poller = Helpers.portIsOwned(@process.pid, @port, @opts.restart.timeout)
							.then ((result) =>
								unless result is 'cancelled'
									verbose "Port #{@port} is successfully owned."
									@started.resolve()
									delete @port_poller
								else
									verbose "Port polling cancelled."
							), @started.reject

	env: -> super() + "#{@opts.portVariable}=\"#{@port}\""
	Server.defaults = (opts) ->
		opts = $.extend {
			port: 8001
			portVariable: "PORT"
			poolName: "shepherd_pool"
		}, Child.defaults opts
		opts.port = parseInt opts.port, 10
		opts.check = $.extend {
			enabled: false
			url: "/"
			status: 200
			contains: null
			timeout: 3000
			interval: 10000
		}, opts.check
		return opts

$.extend module.exports, { Server, Worker }
