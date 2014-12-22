[$, Os, Fs, Handlebars, Shell, Process, { Server, Worker },
	Http, Opts, Helpers, Rabbit, Convert, Jade] =
[ 'bling', 'os', 'fs', 'handlebars', 'shelljs', './process', './child',
	'./http', './opts', './helpers', 'rabbit-pubsub', './convert', 'jade'
].map require

# loggers
log = $.logger "[herd-#{$.random.string 4}]"
verbose = -> if Opts.verbose then log.apply null, arguments

# constants
listen_retry_interval = 200 # ms
stop_delay            = 300 # ms
default_stop_timeout  = Convert(30).seconds.to.ms
clean_exit_code       = 0
dirty_exit_code       = 1

renderView = (view, args) ->
	return Jade.renderFile __dirname + "/../views/" + view, args

module.exports = \
class Herd
	constructor: (opts) ->
		@opts = Herd.defaults(opts)
		@shepherdId = [Os.hostname(), @opts.admin.port].join(":")
		@children = []
		connectSignals @ # register our process signal handlers
		# create Server objects
		for opts in @opts.servers
			for index in [0...opts.count] by 1
				verbose "Creating server:", opts, index
				@children.push new Server opts, index
		# create Worker objects
		for opts in @opts.workers
			for index in [0...opts.count] by 1
				verbose "Creating worker:", opts, index
				@children.push new Worker opts, index

		Http.get "/", (req, res) ->
			packageFile = __dirname + "/../package.json"
			Helpers.readJson(packageFile).wait (err, data) ->
				if err then res.fail err
				else res.pass { name: data.name, version: data.version }
		Http.get "/tree", (req, res) ->
			Process.findTree( pid: process.pid ).then (tree) ->
				res.pass Process.printTree(tree)
		Http.get "/tree/json", (req, res) ->
			Process.findTree( pid: process.pid ).then res.pass
		Http.get "/console", (req, res) =>
			Process.findTree( pid: process.pid ).then (tree) =>
				try return res.html renderView("console.jade", {
					hostname: Os.hostname()
					opts: JSON.stringify @opts
					tree: JSON.stringify tree
				})
				catch err then return res.pass String err.stack ? err
		Http.get "/stop", (req, res) =>
			@stop("SIGTERM").then (->
				res.pass "Children stopped, closing server."
				$.delay stop_delay, process.exit
			), res.fail
		Http.get "/reload", (req, res) =>
			@restart()
			res.redirect 302, "/tree"

		my = (o) => $.extend { shep: @shepherdId }, o
		r = @opts.rabbitmq
		if r.enabled and r.url and r.channel
			verbose "Connecting to #{r.url} channel: #{r.channel}..."
			Rabbit.connect r.url
			Rabbit.subscribe r.channel, { op: "get-status" }, (msg) =>
				log "ack receipt of get-status", msg
				Process.findTree({ pid: process.pid }).then (tree) =>
					reply = $.extend { shep: @shepherdId }, msg, { op: "status-reply", tree: tree }
					Rabbit.publish r.channel, reply
					log "replying to get-status:", reply
			Rabbit.subscribe r.channel, my( op: "stop" ), (msg) =>
				@stop("SIGTERM").then ->
					$.delay stop_delay, process.exit
			Rabbit.subscribe r.channel, my( op: "reload" ), (msg) =>
				@restart()

	setStatus: (@status, args) ->
		verbose "Changing status to:", @status
		Rabbit.publish @opts.rabbitmq.channel, {
			op: "set-status"
			status: @status
			args: args
			shep: @shepherdId
		}

	start: (p = $.Promise()) ->
		@setStatus "starting"
		try return p
		finally listen(@).then (=> # start the admin server
			p.then (=> @setStatus "started"), ((err) => @setStatus "failed: #{String err}")
			log "Admin server listening on port:", @opts.admin.port
			fail = (msg, err) ->
				msg = String(msg) + String(err.stack ? err)
				verbose msg
				p.reject msg
			if checkConflict @opts.servers then fail "port range conflict"
			else
				writeConfig(@).then ((msg) => # write the dynamic configuration
					verbose msg
					@restart().then p.resolve, p.reject
				), p.reject
		), p.reject

	stop: (signal, timeout=default_stop_timeout) ->
		@setStatus "stopping"
		log "Stopping all children with", signal
		try return p = $.Progress 1
		finally
			for child in @children when child.process
				verbose "Attempting to stop child:", child.process.pid, signal
				try p.include child.stop signal
				catch err
					log "Error stopping child:", err.stack ? err
					p.reject err
			holder = setTimeout (->
				log "Failed to stop children within #{timeout} seconds."
				p.reject "timeout"
			), timeout
			p.finish(1).then (=>
				@setStatus "stopped"
				clearTimeout holder
			), (err) ->
				@setStatus "failed to stop", err?.stack ? err

	restart: (from = 0, done = $.Promise()) -> # perform a careful rolling restart
		if from is 0 then verbose "Rolling restart starting..."
		try return done
		finally
			next = => @restart from + 1, done
			child = @children[from]
			switch true
				# if the from index is past the end
				when from >= @children.length
					verbose "Rolling restart finished."
					done.resolve()
				# if there is no such server
				when not child? then done.reject "invalid child index: #{from}"
				else verbose "Rolling restart:", from, child.restart().then next, done.reject

	# use opts.poolName and opts.nginx.template to render the 'upstream' block for nginx
	buildNginxConfig = (self) ->
		s = ""
		pools = Object.create null
		for child in self.children
			if 'poolName' of child.opts and 'port' of child
				(pools[child.opts.poolName] or= []).push child
		for upstream, servers of pools
			s += self.opts.nginx.template({ upstream, servers, pre: "", post: "" })
		verbose "nginx configuration:\n", s
		s

	# write the nginx config to a file
	writeConfig = (self) ->
		nginx = self.opts.nginx
		try return p = $.Promise()
		finally if (not nginx.enabled) or (not nginx.config)
			p.resolve("Nginx configuration not enabled.")
		else
			fail = (msg, err) -> p.reject(msg + (err.stack ? err))
			try
				verbose "Writing nginx configuration to file:", nginx.config
				Fs.writeFile nginx.config, buildNginxConfig(self), (err) ->
					if err then fail "Failed to write nginx configuration file:", err
					else Process.exec(nginx.reload).wait (err) ->
						if err then fail "Failed to reload nginx:", err
						else p.resolve("Nginx configuration written.")
			catch err then fail "writeConfig exception:", err

	listen = (self, p = $.Promise()) ->
		port = self.opts.admin.port
		p.then $.identity, (err) ->
			self.setStatus "listen failed: #{ err?.stack ? err }"
		try return p
		finally Process.clearCache().findOne({ ports: port }).then (owner) ->
			if owner?
				log "Killing old listener on port (#{port}): #{owner.pid}"
				Process.kill(owner.pid, "SIGTERM").then ->
					log "Will retry after #{listen_retry_interval} ms"
					$.delay listen_retry_interval, -> listen self, p
			else Http.listen(port).then p.resolve, p.reject

	checkConflict = (servers) ->
		ranges = ([server.port, server.port + server.count - 1] for server in servers)
		for a in ranges
			for b in ranges
				switch true
					when a is b then continue
					when a[0] <= b[0] <= a[1] or a[0] <= b[1] <= a[1]
						verbose "Conflict in port ranges:", a, b
						return true
		false

	connectSignals = (self) ->
		clean_exit = -> log "Exiting clean..."; process.exit clean_exit_code
		dirty_exit = (err) -> console.error(err); process.exit dirty_exit_code

		# on SIGINT or SIGTERM, kill everything and die
		for sig in ["SIGINT", "SIGTERM"] then do (sig) ->
			process.on sig, ->
				log "Got signal:", sig
				self.stop("SIGKILL").then clean_exit, dirty_exit

		# on SIGHUP, just reload all child procs
		process.on "SIGHUP", ->
			log "Got signal: SIGHUP... reloading."
			self.restart()

		process.on "exit", (code) ->
			log "shepherd.on 'exit',", code

# make sure a herd object has all the default configuration
Herd.defaults = (opts) ->
	opts = $.extend Object.create(null), {
		servers: []
		workers: []
	}, opts

	opts.rabbitmq = $.extend Object.create(null), {
		enabled: false
		url: "amqp://localhost:5672"
		channel: "shepherd"
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
			reload: "echo WARN: I don't know how to reload nginx on platform: " + Os.platform()
		), opts.nginx

	opts.nginx.template or= """
		upstream {{upstream}} {
			{{pre}}
			{{#each servers}}
			server 127.0.0.1:{{this.port}} weight=1;
			{{/each}}
			{{post}}
			keepalive 32;
		}
	"""
	opts.nginx.template = Handlebars.compile opts.nginx.template
	opts.nginx.template.inspect = (level) -> # use a mock rendering as standard output
		return '"' + opts.nginx.template({
			upstream: "{{upstream}}",
			pre: "{{#each servers}}"
			servers: [ { port: "{{this.port}}" } ]
			post: "{{/each}}"
		}) + '"'

	# the http server listens for REST calls and web hooks
	opts.admin = $.extend Object.create(null), {
		enabled: true
		port: 9000
	}, opts.admin

	verbose "Using configuration:", JSON.stringify(opts, null, '  ')

	return opts
