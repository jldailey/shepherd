$       = require 'bling'
Os      = require "os"
Shell   = require 'shelljs'
Process = require './process'
Helpers = require './helpers'
Http    = require './http'
Handlebars = require "handlebars"
log = $.logger "[child]"

class Child
	constructor: (opts, index) ->
		$.extend @,
			opts: opts
			index: index
			process: null
			started: $.extend $.Promise(),
				attempts: 0
				timeout: null
			log: $.logger @toString()

	start: ->
		try return @started
		finally
			fail = (msg) -> @started.reject msg
			if ++@started.attempts > @opts.restart.maxAttempts
				fail "too many attempts"
			else
				clearTimeout @started.timeout
				@started.timeout = setTimeout (=> @started.attempts = 0), @opts.restart.maxInterval
				log "shell >" , cmd = "env #{@env()} bash -c 'cd #{@opts.cd} && #{@opts.command}'"
				@process = Shell.exec cmd, { silent: true, async: true }, $.identity
				@process.on "exit", (code) => @onExit code
				on_data = (prefix = "") => (data) =>
					for line in String(data).split /\n/ when line.length
						@log prefix + line
				@process.stdout.on "data", on_data ""
				@process.stderr.on "data", on_data "(stderr) "
				unless @process.pid then fail "no pid"
				# IMPORTANT NOTE: does not resolve @started on it's own,
				# a sub-class like Server or Worker is expected to @started.resolve()

	stop: (signal) ->
		@started.attempts = Infinity
		try return p = $.Promise()
		finally
			unless @process? then p.reject 'no process'
			else
				@process.on 'exit', p.resolve
				Process.kill @process.pid, signal

	restart: ->
		try return p = $.Promise()
		finally unless @process? then @start().then p.resolve, p.reject
		else
			restart = =>
				log "Restarting child..."
				@process = null
				@started.reset()
				@start().then p.resolve, p.reject
			log "Killing existing process", @process.pid
			Process.killTree(@process.pid, "SIGTERM").wait @opts.restart.gracePeriod, (err) ->
				if err is "timeout"
					log "Child failed to die within #{@opts.restart.gracePeriod}ms, escalating to SIGKILL"
					Process.killTree(@process.pid, "SIGKILL")
						.then restart, p.reject
				else if err then p.reject err
				else restart()

	onExit: (exitCode) ->
		return unless @process?
		@log "Child PID: #{@process.pid} exited:", exitCode
		# Record the death of the child
		@process = null
		# if it died with a restartable exit code, attempt to restart it
		if exitCode isnt 0
			@start()

	toString: -> "[(#{@process?.pid}):#{@port}]"
	inspect:  -> "[(#{@process?.pid}):#{@port}]"
	env: -> ("#{key}=\"#{val}\"" for key,val of @opts.env when val?).join " "

	Child.defaults = (opts) -> # make sure each server block in the configuration has the minimum defaults
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
		return "[" +
			("[#{worker.process?.pid ? "DEAD"}, :#{worker.port}]" for worker in workers).join ",\n"
		+ "]"
	Http.get "/workers/restart", (req, res) ->
		for worker in workers
			worker.restart()
		res.redirect 302, "/workers?restarting"
	workers = []

	constructor: (opts, index) ->
		Child.apply @, [
			opts = Worker.defaults opts,
			index
		]
		workers.push @
		@log = $.logger @toString()

	toString: -> "(#{@opts.cd})[#{@index}]"
	inspect: -> @toString()

	start: ->
		Child::start.apply @, p
		@started.resolve()

	Worker.defaults = Child.defaults

class Server extends Child
	Http.get "/servers", (req, res) ->
		ret = "["
		for port,servers of servers
			for server in servers
				ret += "[#{server.process?.pid ? "DEAD"}, :#{server.port}],\n"
		ret += "]"
		res.pass ret
	Http.get "/servers/restart", (req, res) ->
		for port,v of servers
			for server in v
				server.restart()
		res.redirect 302, "/servers?restarting"

	# a map of base port to all Server instances based on that port
	servers = {}

	constructor: (opts, index) ->
		Child.apply @, [
			opts = Server.defaults opts,
			index
		]
		@port = opts.port + index
		@log = $.logger "(#{@opts.cd}):#{@port}"
		(servers[opts.port] ?= []).push @

	# wrap the default start function
	start: () ->
		try return @started
		finally
			_start = Child::start
			# find any process that is listening on our port
			Process.clearCache().findOne({ ports: @port }).then (owner) =>
				if owner? # if the port is being listened on
					@log "Killing previous owner of", @port, "PID:", owner.pid
					Process.killTree(owner, "SIGKILL").then =>
						@start()
				else # port is available, so really start
					_start.apply(@)
					log "Waiting for port", @port, "to be owned by", @process.pid
					Helpers.portIsOwned(@process.pid, @port, @opts.restart.timeout)
						.then @started.resolve, @started.reject

	stop: ->
		Child::stop.apply(@)
		try return p = $.Promise()
		finally if @process
			Process.killTree(@process.pid, "SIGTERM").then p.resolve, p.reject
		else p.resolve()

	env: ->
		ret = Child::env.apply @
		ret += "#{@opts.portVariable}=\"#{@port}\""
		ret
	Server.defaults = (opts) ->
		opts = $.extend {
			port: 8001
			portVariable: "PORT"
			poolName: "shepherd_pool"
		}, Child.defaults opts
		opts.port = parseInt opts.port, 10
		opts

$.extend module.exports, { Server, Worker }
