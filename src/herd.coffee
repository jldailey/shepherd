[$, Os, Fs, Handlebars, Shell, Process, { Server, Worker }, Http, Opts ] =
	[ 'bling', 'os', 'fs', 'handlebars', 'shelljs',
		'./process', './child', './http', './opts'
	].map require
log = $.logger "[herd]"
verbose = -> if Opts.verbose then log.apply null, arguments

die = ->
	log.apply null, arguments
	process.exit 1

module.exports = class Herd

	constructor: (opts) ->
		@opts = Herd.defaults(opts)
		@shepherdId = [Os.hostname(), @opts.admin.port].join(":")
		@children = []
		for opts in @opts.servers
			for index in [0...opts.count] by 1
				@children.push new Server opts, index
		for opts in @opts.workers
			for index in [0...opts.count] by 1
				@children.push new Worker opts, index

		Http.get "/", (req, res) ->
			Helpers.readJson "../package.json", (err, data) ->
				if err then res.fail err
				else res.pass { name: data.name, version: data.version }
		Http.get "/tree", (req, res) ->
			Process.findOne({ pid: process.pid }).then (proc) ->
				Process.summarize(proc).then (tree) ->
					res.pass Process.printTree(tree)

		connectRabbit  @ # connect to rabbitmq
		connectSignals @ # register our process signal handlers

	start: (p = $.Promise()) ->
		try return p
		finally listen(@).then (=> # start the admin server
			log "Admin server listening on port:", @opts.admin.port
			if checkConflict @opts.servers
				p.reject "port range conflict in servers"
			else
				writeConfig(@).then (=> # write the nginx configuration
					@restart().then p.resolve, p.reject
				), p.reject
		), p.reject

	stop: (signal) ->
		log "Stopping all children with", signal
		try return p = $.Progress 1
		finally
			for child in @children when child.process
				log "Stopping child:", child.process.pid
				p.include Process.killTree { pid: child.process.pid }, signal
			p.finish(1).then (-> log "Fully stopped."), (err) -> log "Failed to stop:", err

	restart: (from = 0, done = $.Promise()) -> # perform a careful rolling restart
		try return done
		finally
			next = => @restart from + 1, done
			child = @children[from]
			switch
				# if the from index is past the end
				when from >= @children.length
					verbose "Rolling restart finished."
					done.resolve()
				# if there is no such server
				when not child? then done.reject "invalid child index: #{from}"
				when not child.process? then verbose "Rolling start:", from, child.start().then next, done.reject
				# else, an old child process is running
				else
					log "Killing existing process", child.process.pid
					Process.killTree(child.process.pid, "SIGTERM").wait child.opts.restart.gracePeriod, (err) ->
						if err is "timeout"
							log "Child failed to die within #{child.opts.restart.gracePeriod}ms, escalating to SIGKILL"
							Process.killTree(child.process.pid, "SIGKILL")
								.then -> child.started.then next, done.reject
						else if err then done.reject err
						else child.started.then next, done.reject

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

	connectSignals = (self) ->
		clean_exit = -> log "Exiting clean..."; process.exit 0
		dirty_exit = (err) -> console.error(err); process.exit 1

		# on SIGINT or SIGTERM, kill everything and die
		for sig in ["SIGINT", "SIGTERM"] then do (sig) ->
			process.on sig, ->
				log "Got signal:", sig
				self.stop("SIGKILL").then clean_exit, dirty_exit

		# on SIGHUP, just reload all child procs
		process.on "SIGHUP", ->
			self.restart()

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

	collectStatus = (pids) -> Process.find { pid }

# make sure a herd object has all the default configuration
Herd.defaults = (opts) ->
	opts = $.extend Object.create(null), {
		servers: []
		workers: []
	}, opts
	# the above has two effects:
	# - allows calling without arguments
	# - ensures that the opts object can't be polluted by Object.prototype

	opts.rabbitmq = $.extend Object.create(null), {
		enabled: false
		url: "amqp://localhost:5672"
		exchange: "shepherd"
	}, opts.rabbitmq

	opts.nginx = $.extend Object.create(null), (switch Os.platform()
		when 'darwin'
			enabled: true
			config: "/usr/local/etc/nginx/conf.d/shepherd.conf"
			reload: "launchctl stop homebrew.mxcl.nginx && launchctl start homebrew.mxcl.nginx"
		when 'linux'
			enabled: true
			config: "/etc/nginx/conf.d/shepherd.conf"
			reload: "/etc/init.d/nginx reload"
		else
			enabled: false
			config: null
			reload: "echo I don't know how to reload nginx on platform: " + Os.platform()
		), opts.nginx

	opts.admin = $.extend Object.create(null), { # the http server listens for REST calls and web hooks
		enabled: true
		port: 9000
	}, opts.admin

	verbose "Using configuration:", require('util').inspect(opts)

	return opts
