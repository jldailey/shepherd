[$, Os, Fs, Handlebars, Shell, Process, { Server, Worker },
	Http, Opts, Helpers, Rabbit ] =
[ 'bling', 'os', 'fs', 'handlebars', 'shelljs', './process', './child',
	'./http', './opts', './helpers', './rabbit'
].map require

log = $.logger "[herd-#{$.random.string 4}]"
verbose = -> if Opts.verbose then log.apply null, arguments

module.exports = class Herd

	constructor: (opts) ->
		@opts = Herd.defaults(opts)
		@shepherdId = [Os.hostname(), @opts.admin.port].join(":")
		@children = []
		connectSignals @ # register our process signal handlers
		for opts in @opts.servers
			for index in [0...opts.count] by 1
				verbose "Creating server:", opts, index
				@children.push new Server opts, index
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
			Process.findTree({ pid: process.pid }).then (tree) ->
				res.pass Process.printTree(tree)
		Http.get "/stop", (req, res) =>
			@stop("SIGTERM").then (->
				res.pass "Children stopped, closing server."
				$.delay 300, process.exit
			), res.fail
		Http.get "/reload", (req, res) =>
			@restart()
			res.redirect 302, "/tree"

		r = @opts.rabbitmq
		if r.enabled and r.url
			Rabbit = require './rabbit'
			Rabbit.connect(r.url)
			my = (o) => extend { id: @shepherdId }, o
			Rabbit.match { op: "ping" }, (msg) ->
				Process.findTree({ pid: process.pid }).then (tree) ->
					Rabbit.publish my { op: "pong", tree: tree }
			Rabbit.match my( op: "stop" ), (msg) =>
				@stop("SIGTERM").then ->
					Rabbit.publish my { op: "stopped" }
					$.delay 300, process.exit
			Rabbit.match my( op: "reload" ), (msg) ->
				@restart()
				Rabbit.publish my { op: "restarting" }


	start: (p = $.Promise()) ->
		try return p
		finally listen(@).then (=> # start the admin server
			log "Admin server listening on port:", @opts.admin.port
			fail = (msg, err) ->
				msg = String(msg) + String(err.stack ? err)
				verbose msg
				p.reject msg
			if checkConflict @opts.servers then fail "port range conflict"
			else
				writeConfig(@).then (=> # write the dynamic configuration
					verbose "Nginx configuration written."
					@restart().then p.resolve, p.reject
				), p.reject
		), p.reject

	seconds = (ms) -> ms / 1000

	stop: (signal, timeout=30000) ->
		log "Stopping all children with", signal
		try return p = $.Progress 1
		finally
			for child in @children when child.process
				try p.include child.stop signal
				catch err
					log "Error stopping child:", err.stack ? err
					p.reject err
			holder = setTimeout (->
				log "Failed to stop children within #{seconds timeout} seconds."
			), timeout
			p.finish(1).then (->
				log "Fully stopped."
				clearTimeout holder
			), (err) -> log "Failed to stop:", err

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
			p.resolve()
		else
			fail = (msg, err) -> p.reject(msg + (err.stack ? err))
			try
				verbose "Writing nginx configuration to file:", nginx.config
				Fs.writeFile nginx.config, buildNginxConfig(self), (err) ->
					if err then fail "Failed to write nginx configuration file:", err
					else Process.exec(nginx.reload).wait (err) ->
						if err then fail "Failed to reload nginx:", err
						else p.resolve()
			catch err then fail "writeConfig exception:", err

	listen = (self, p = $.Promise()) ->
		port = self.opts.admin.port
		try return p
		finally Process.clearCache().findOne({ ports: port }).then (owner) ->
			if owner?
				log "Killing old listener on port (#{port}): #{owner.pid}"
				Process.clearCache().kill(owner.pid, "SIGTERM").then -> $.delay 100, -> listen self
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
		clean_exit = -> log "Exiting clean..."; process.exit 0
		dirty_exit = (err) -> console.error(err); process.exit 1

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


	collectStatus = (pids) ->
		$.Promise.collect (Process.find { pid } for pid in pids)

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

	verbose "Using configuration:", require('util').inspect(opts)

	return opts
