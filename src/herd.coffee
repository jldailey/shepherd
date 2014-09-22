[$, Os, Fs, Handlebars, Shell, Process, Server, Worker, Http, Opts ] =
	[ 'bling', 'os', 'fs', 'handlebars', 'shelljs',
		'./process', './server', './worker', './http', './opts'
	].map require
log = $.logger("[herd]")

# clean all non-simple stuff out of an object
sanitizeObject = (obj) -> JSON.parse JSON.stringify obj

# spawn of bunch of Worker or Server items
# stuff is a list of item definitions, e.g. opts.workers or opts.servers from the config
# klass is either Server or Worker
spawnAll = (stuff, klass) ->
	i = 0
	$(stuff).map((item) ->
		log "Spawning", item.count, klass.name + "s"
		try return a = []
		finally for j in [0...server.count] by 1
			a.unshift new klass(item), i++
			log "Spawning a", klass.name
			a[0].spawn()
	).flatten()

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
			@servers = spawnAll @opts.servers, Server # start all the servers
			@workers = spawnAll @opts.workers, Worker # start all the workers
			writeConfig(@).then p.resolve, p.reject # write the nginx config (if enabled)

	restart: ->
		try return p = $.Progress(2)
		finally
			step = (-> p.finish 1)
			restart.servers().then step, p.reject
			restart.workers().then step, p.reject

	setStatus: (status, opts) ->
		if Opts.verbose then log "Setting status: ", status, opts ? ""
		@rabbitmq.publish $.extend {
			op: "status",
			status: @status = sanitizeObject status
			from: @shepherdId
		}, if opts? then sanitizeObject opts else null

	writeConfig = (self) ->
		nginx = self.opts.nginx
		try return p = $.Promise()
		finally if nginx.config
			if Opts.verbose then log "Writing nginx configuration to file:", nginx.config
			Fs.writeFile nginx.config, buildNginxConfig(self), (err) ->
				if err? then log "Failed to write nginx config file:", err
				else
					log("Nginx reload:", nginx.reload)
					Process.exec(nginx.reload).wait (err) ->
						if err then log("Failed to reload nginx:", err)

	listen = (self, p = $.Promise()) ->
		port = self.opts.admin.port
		try return p
		finally Process.findOne({ ports: port }).then (owner) ->
			if owner?
				log "Killing old listener on admin port ("+port+"): "+owner.pid
				owner.kill("SIGKILL").then -> listen(self)
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
				if Opts.verbose then log("Rolling restart:", from)
				switch
					when from >= self.servers.length     then done.resolve()
					when not self.servers[from]?         then done.reject "invalid server index: #{from}"
					when not self.servers[from].process? then self.servers[from].spawn().then next, done.reject
					else self.servers[from].kill("SIGTERM").wait self.opts.restart.gracePeriod, (err) ->
						if err then done.reject err
						else self.servers[from].started.then next, done.reject
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


	killAll = (stuff, signal) ->
		unless stuff.length then return $.Promise().resolve()
		try return p = $.Progress stuff.length
		finally for thing in stuff when thing?.process?
			Process.tree(thing.process).then (tree) ->
				Process.walk tree, (proc) -> p.include proc.kill signal
				thing.process = null
				p.finish 1
	killAll: (signal) ->
		p = $.Progress 1
		p.include killAll @servers, signal
		p.include killAll @workers, signal
		return p.finish 1

# make sure a herd object has all the default configuration
Herd.defaults = (opts) ->
	log "Filling in opts:", opts

	opts = $.extend Object.create(null), opts
	# the above has two effects: allows calling without arguments
	# and ensures that the opts object can't be polluted by Object.prototype

	if 'exec' in opts
		opts.server = opts.exec
		delete opts.exec

	if $.is 'object', opts.servers
		opts.servers = [ opts.servers ]
	else if $.is 'object', opts.server
		opts.servers = [ opts.server ]
	else if $.is 'array', opts.server
		opts.servers = opts.server
	delete opts.server

	if not $.is 'array', opts.servers
		log "Invalid value for 'servers' in config json", opts
		process.exit 1

	opts.servers = $(opts.servers).map((server) ->

		server = $.extend Object.create(null), {
			cd: "."
			cmd: "node index.js"
			count: Math.max(1, Os.cpus().length - 1)
			port: 8000, # a starting port, each child after the first will increment this
			portVariable: "PORT", # and set it in the env using this variable
			env: {}
		}, server

		server.port = parseInt server.port, 10
		server.count = parseInt server.count, 10

		while server.count < 0
			server.count += Os.cpus().length

		# control what happens at (re)start time
		server.restart = $.extend Object.create(null), {
			maxAttempts: 5, # failing five times fast is fatal
			maxInterval: 10000, # in what interval is "fast"?
			gracePeriod: 3000, # how long to wait for a forcibly killed process to die
			timeout: 10000, # how long to wait for a newly launched process to start listening on it's port
		}, server.restart

		server.git = $.extend Object.create(null), {
			remote: "origin"
			branch: "master"
			command: "git pull {{remote}} {{branch}} || git merge --abort"
		}, server.git

		server.git.command = Handlebars.compile(server.git.command)
		server.git.command.inspect = (level) ->
			return '"' + server.git.command({ remote: "{{remote}}", branch: "{{branch}}" }) + '"'

		return server

	)


	opts.rabbitmq = $.extend Object.create(null), {
		enabled: true
		url: "amqp://localhost:5672"
		exchange: "shepherd"
	}, opts.rabbitmq

	switch Os.platform()
		when 'darwin'
			opts.nginx = $.extend Object.create(null), {
				config: "/usr/local/etc/nginx/conf.d/shepherd_pool.conf"
				reload: "launchctl stop homebrew.mxcl.nginx && launchctl start homebrew.mxcl.nginx" # only used if nginx.config is set to a writeable filename
			}, opts.nginx
			break
		when 'linux'
			opts.nginx = $.extend Object.create(null), {
				config: "/etc/nginx/conf.d/shepherd_pool.conf"
				reload: "/etc/init.d/nginx reload" # only used if nginx.config is set to a writeable filename
			}, opts.nginx
			break
		else
			opts.nginx = $.extend Object.create(null), {
				config: null
				reload: "echo I dont know how to reload nginx on platform: " + Os.platform()
			}, opts.nginx
			log "Unknown platform:", Os.platform(), "nginx defaults will be meaningless."

	opts.admin = $.extend Object.create(null), { # the http server listens for REST calls and webhooks
		port: 9000
	}, opts.admin

	# "worker" can be set in the config json
	# but it just morphs into the "workers" array with one item in it
	if $.is 'object', opts.worker
		opts.workers = [ opts.worker ]
		delete opts.worker
	# and then "worker" becomes read-only (see: "workers" array)
	$.defineProperty opts, "worker",
		get: -> return opts.workers[0]

	if not $.is 'array', opts.workers
		opts.workers = []

	opts.workers = $(opts.workers).map (w) -> $.extend Object.create(null), {
		count: 1
		cd: "."
		cmd: "echo No worker cmd specified"
	}, w

	if Opts.verbose then log "Using configuration:", require('util').inspect(opts)

	return opts

connectSignals = (self) ->

	clean_exit = -> log "Exiting clean..."; process.exit 0
	dirty_exit = (err) -> console.log(err); process.exit 1

	# on SIGINT or SIGTERM, kill everything and die
	for sig in ["SIGINT", "SIGTERM"]
		process.on sig, ->
			self.killAll("SIGKILL").then clean_exit, dirty_exit

	# on SIGHUP, just reload all child procs
	process.on "SIGHUP", ->
		self.restartAll()

	# hook up a broadcaster to announce our demise
	for sig in ["exit", "SIGINT", "SIGTERM"] then do (sig) ->
		process.on sig, ->
			self.setStatus "offline", { signal: sig }

connectHttp = (self) ->

	# a decorator for a plain-text request handler
	plain = (f) -> (req, res) ->
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
	r.publish = r.subscribe = $.identity
	fail = (err) -> log err?.stack ? err
	if r.enabled and r.url
		require('./amqp').connect(r.url).then (context) ->
			r.publish = (message) ->
				pub = context.socket("PUB")
				pub.connect r.exchange, ->
					pub.end JSON.stringify(message), 'utf8'
			r.subscribe = (handler) ->
				sub = context.socket "SUB"
				sub.connect r.exchange, ->
					sub.on 'data', on_data = (data) -> handler JSON.parse String data
					sub.on 'drain', on_data
			# announce our status
			self.setStatus self.status ? "online"


	rabbitRoute = (pattern, handler) -> $.publish("amqp-route", self.rabbitmq.exchange, pattern, handler)
	# Restart all via AMQP message:
	rabbitRoute { to: self.shepherdId, op: "restart" }, self.restartAll.bind self
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
			(pools[server.opts.upstream] or= []).push server
		for upstream of pools
			s += "upstream #{upstream} {\n"
			for server in pools[upstream]
				s += "\tserver 127.0.0.1:#{server.port};\n"
			s += "}\n"
		log("nginx config:\n", s)

getProcessSummary = (proc) -> # sums up the memory and CPU usage of the whole process tree under this process
	sum = { pid: proc.pid, rss: 0, cpu: 0 }
	try return p = $.Promise()
	finally Process.tree(proc).then (tree) ->
		Process.walk(tree, (proc) ->
			sum.rss += proc.rss
			sum.cpu += proc.cpu
		).then (-> p.resolve sum), p.reject

collectStatus = (pids) ->
	return $.Promise.collect pids.map (pid) ->
		return if pid? then Process.findOne { pid }
		else $.Promise.resolve { pid: "DEAD", rss: 0, cpu: 0 }
