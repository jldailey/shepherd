[$, Os, Fs, Handlebars, Shell, Process, Server, Worker, Http, Opts ] =
	[ 'bling', 'os', 'fs', 'handlebars', 'shelljs',
		'./process', './server', './worker', './http', './opts'
	].map require
log = $.logger("[herd]")
verbose = -> if Opts.verbose then log.apply null, arguments

die = ->
	log.apply null, arguments
	process.exit 1

# clean all non-simple stuff out of an object
sanitizeObject = (obj) -> JSON.parse JSON.stringify obj

# create a bunch of Worker or Server items
# stuff is a list of item definitions, e.g. opts.workers or opts.servers from the configuration
# klass is either Server or Worker
initAll = (stuff, klass) ->
	$(stuff).map((item) ->
		log "Creating", item.count, klass.name + "s"
		try return a = []
		finally for j in [0...item.count] by 1
			a.push new klass item, j
	).flatten()

killAll = (stuff, signal) ->
	unless stuff.length then return $.Promise().resolve()
	try return p = $.Progress stuff.length
	finally for thing in stuff when thing?.process?
		Process.tree(thing.process).then (tree) ->
			Process.walk tree, (proc) -> p.include proc.kill signal
			thing.process = null
			p.finish 1

module.exports = class Herd
	constructor: (opts) ->
		@opts = Herd.defaults(opts)
		@shepherdId = [Os.hostname(), @opts.admin.port].join(":")
		connectRabbit  @ # connect to rabbitmq
		connectHttp    @ # connect our web routes
		connectSignals @ # register our process signal handlers
		@setStatus "online"

	start: ->
		try return p = $.Promise()
		finally listen(@).then => # start the admin server
			if checkConflict @opts.servers then return p.reject "port range conflict"
			@servers = initAll @opts.servers, Server # start all the servers
			@workers = initAll @opts.workers, Worker # start all the workers
			writeConfig(@).then p.resolve, p.reject # write the nginx config (if enabled)
			restart.workers(@).then =>
				restart.servers(@)

	stop: (signal) ->
		p = $.Progress 1
		p.include killAll @servers, signal
		p.include killAll @workers, signal
		return p.finish 1

	restart: ->
		try return p = $.Progress(2)
		finally
			step = (-> p.finish 1)
			restart.servers(@).then step, p.reject
			restart.workers(@).then step, p.reject

	setStatus: (status, opts) ->
		verbose "Setting status:", status, opts ? ""
		@rabbitmq.publish $.extend {
			op: "status",
			status: @status = sanitizeObject status
			from: @shepherdId
		}, if opts? then sanitizeObject opts else null

	writeConfig = (self) ->
		nginx = self.opts.nginx
		try return p = $.Promise()
		finally if nginx.config
			if not nginx.enabled then p.resolve()
			else
				verbose "Writing nginx configuration to file:", nginx.config
				Fs.writeFile nginx.config, buildNginxConfig(self), (err) ->
					if err then log "Failed to write nginx configuration file:", err
					else Process.exec(nginx.reload).wait (err) ->
						if err then log "Failed to reload nginx:", err

	listen = (self, p = $.Promise()) ->
		port = self.opts.admin.port
		try return p
		finally Process.clearCache().findOne({ ports: port }).then (owner) ->
			if owner?
				log "Killing old listener on port (#{port}): #{owner.pid}"
				Process.clearCache().kill(owner.pid, "SIGTERM").then -> $.delay 100, -> listen self
			else Http.listen(port).then p.resolve, p.reject

	checkConflict = (servers) ->
		ranges = [server.port, server.port + server.count - 1] for server in servers
		for a in ranges
			for b in ranges
				if a[0] <= b[0] <= a[1] or a[0] <= b[1] <= a[1]
					return true
		false

	restart = { # hold in a little dictionary so we can look them up by name easily later
		servers: (self, from = 0, done = $.Promise()) -> # perform a careful rolling restart
			try return done
			finally
				next = -> restart.servers self, from + 1, done
				verbose "Rolling restart:", from
				server = self.servers[from]
				switch
					# if the from index is past the end
					when from >= self.servers.length     then done.resolve()
					# if there is no such server
					when not server?         then done.reject "invalid server index: #{from}"
					# if the server has no process yet
					when not server.process? then server.spawn().then next, done.reject
					# else, an old server process is running
					else server.kill("SIGTERM").wait server.opts.restart.gracePeriod, (err) ->
						if err is "timeout"
							log "Server failed to die within #{server.opts.restart.gracePeriod}ms, escalating to SIGKILL"
							server.kill("SIGKILL").then -> server.started.then next, done.reject
						else if err then done.reject err
						else server.started.then next, done.reject
		workers: (self) -> # kill and restart all workers at once
			try return p = $.Promise().resolve()
			finally for worker in self.workers
				if worker.process?
					log "Killing old worker:", worker.process.pid
					Process.find({ ppid: worker.process.pid }).then (procs) ->
						pids = $(procs).select('pid').join(" ")
						log "Killing all worker children:", pids
						Shell.exec "kill -15 " + pids
				else
					log "Launching fresh worker..."
					worker.spawn()
	}

	connectSignals = (self) ->
		clean_exit = -> log "Exiting clean..."; process.exit 0
		dirty_exit = (err) -> console.error(err); process.exit 1

		# on SIGINT or SIGTERM, kill everything and die
		for sig in ["SIGINT", "SIGTERM"]
			process.on sig, ->
				self.stop("SIGKILL").then clean_exit, dirty_exit

		# on SIGHUP, just reload all child procs
		process.on "SIGHUP", ->
			self.restart()

		# hook up a broadcaster to announce our demise
		for sig in ["exit", "SIGINT", "SIGTERM"] then do (sig) ->
			process.on sig, ->
				self.setStatus "offline", { signal: sig }

	connectHttp = (self) ->
		plain = (f) -> (req, res) -> # a decorator for a plain-text request handler
			res.contentType = "text/plain"
			res.send = (status, content, enc = "utf8") ->
				res.statusCode = status
				res.end(content, enc)
			res.pass = (content) -> res.send 200, content
			res.fail = (err) ->
				if err?.stack then res.send 500, err.stack
				else if $.is 'string', err then res.send 500, err
				else res.send 500, JSON.stringify err
			return f(req, res)

		# a macro for registering a route (handled by lib/http.js)
		webRoute = (method, url, handler) -> $.publish "http-route", method, url, plain handler

		addRoutesFor = (name) ->
			plural = name.toLowerCase().replace(/s{0,1}$/, "s")
			proper = name[0].toUpperCase() + name.substring(1).toLowerCase()
			webRoute "get", "/#{plural}", (req, res) ->
				collectStatus($(self[plural]).select 'process.pid').then res.pass, res.fail
			webRoute "get", "/#{plural}/restart", (req, res) ->
				restart[plural] self
				res.redirect 302, "/#{plural}"
			webRoute "get", "/#{plural}/restart/:index", (req, res) ->
				index = parseInt req.params.index, 10
				proc = self[plural][index]
				return res.fail("No such #{proper}.") unless proc?
				proc.kill().wait self.restart.gracePeriod, (err) ->
					if err then return res.fail err
					else res.pass "#{proper} #{index} killed, now it should auto-restart."
		addRoutesFor "workers"
		addRoutesFor "servers"

	connectRabbit = (self) ->
		r = self.opts.rabbitmq
		self.rabbitmq = {
			publish: $.identity
			subscribe: $.identity
		}
		fail = (err) -> log err?.stack ? err
		if r.enabled and r.url
			require('./amqp').connect(r.url).then (context) ->
				$.extend self.rabbitmq, {
					publish: (message) ->
						pub = context.socket("PUB")
						pub.connect r.exchange, ->
							pub.end JSON.stringify(message), 'utf8'
					subscribe: (handler) ->
						sub = context.socket "SUB"
						sub.connect r.exchange, ->
							sub.on 'data', on_data = (data) -> handler JSON.parse String data
							sub.on 'drain', on_data
				}
				# (re-)announce our status
				self.setStatus self.status ? "online"


		rabbitRoute = (pattern, handler) -> $.publish("amqp-route", self.opts.rabbitmq.exchange, pattern, handler)
		# Restart all via AMQP message:
		rabbitRoute { to: self.shepherdId, op: "restart" }, self.restart.bind self
		# Response to a status query via AMQP message:
		rabbitRoute { op: "ping" }, (msg) ->
			unless 'ts' of msg
				return log "Malformed PING message from rabbitmq:", msg
			collectStatus($(self.servers).select 'process.pid').then (servers) ->
				collectStatus($(self.workers).select 'process.pid').then (workers) ->
					self.rabbitmq.publish {
						op: "pong"
						from: self.shepherdId
						ts: $.now, dt: $.now - msg.ts
						status: { servers, workers }
					}

	buildNginxConfig = (self) ->
		pools = Object.create null
		try return s = ""
		finally
			for server in self.servers
				(pools[server.opts.poolName] or= []).push server
			for upstream of pools
				s += "upstream #{upstream} {\n"
				for server in pools[upstream]
					s += "\tserver 127.0.0.1:#{server.port};\n"
				s += "}\n"
			log("nginx configuration:\n", s)

	collectStatus = (pids) ->
		return $.Promise.collect pids.map (pid) ->
			return if pid? then Process.findOne { pid }
			else $.Promise.resolve { pid: "DEAD", rss: 0, cpu: 0 }


# make sure a herd object has all the default configuration
Herd.defaults = (opts) ->
	opts = $.extend Object.create(null), opts
	# the above has two effects: allows calling without arguments
	# and ensures that the opts object can't be polluted by Object.prototype

	# handle all the optional ways to specify the servers to launch
	# { 'exec': { ... } }
	# { 'server': { ... } }
	# { 'servers': [ ... ] }
	# at the end, we will have it in the form of { 'servers': [ ... ] }
	opts.servers = switch
		when $.is 'string', opts.exec then [ { cmd: opts.exec } ]
		when $.is 'string', opts.server then [ { cmd: opts.server } ]
		when $.is 'object', opts.exec then [ opts.exec ]
		when $.is 'object', opts.server then [ opts.server ]
		when $.is 'array', opts.exec then opts.exec
		when $.is 'array', opts.server then opts.server
		else die "Invalid value for 'servers' in config json", opts
	delete opts.exec
	delete opts.server
	opts.servers = $(opts.servers).map(Server.defaults)

	# handle all the optional ways to specify the workers to launch
	# { 'worker': { ... } }
	# { 'workers': [ ... ] }
	# at the end, we will have it in the form of { 'workers': [ ... ] }
	opts.workers = switch
		when $.is 'string', opts.worker then [ { cmd: opts.worker } ]
		when $.is 'object', opts.worker then [ opts.worker ]
		when $.is 'array', opts.worker then opts.worker
		when $.is 'array', opts.workers then opts.workers
		when not opts.workers? then [ ]
		else die "Invalid value for 'workers' in config json", opts.workers
	delete opts.worker
	opts.workers = $(opts.workers).map Worker.defaults

	opts.rabbitmq = $.extend Object.create(null), {
		enabled: true
		url: "amqp://localhost:5672"
		exchange: "shepherd"
	}, opts.rabbitmq

	switch Os.platform()
		when 'darwin'
			opts.nginx = $.extend Object.create(null), {
				enabled: true
				config: "/usr/local/etc/nginx/conf.d/shepherd_pool.conf"
				reload: "launchctl stop homebrew.mxcl.nginx && launchctl start homebrew.mxcl.nginx"
			}, opts.nginx
			break
		when 'linux'
			opts.nginx = $.extend Object.create(null), {
				enabled: true
				config: "/etc/nginx/conf.d/shepherd_pool.conf"
				reload: "/etc/init.d/nginx reload" # only used if nginx.config is set to a writeable filename
			}, opts.nginx
			break
		else
			opts.nginx = $.extend Object.create(null), {
				enabled: false
				config: null
				reload: "echo I don't know how to reload nginx on platform: " + Os.platform()
			}, opts.nginx
			log "Unknown platform:", Os.platform(), "nginx defaults will be meaningless."

	opts.admin = $.extend Object.create(null), { # the http server listens for REST calls and web hooks
		enabled: true
		port: 9000
	}, opts.admin

	verbose "Using configuration:", require('util').inspect(opts)

	return opts
