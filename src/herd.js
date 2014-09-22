var $ = require('bling'),
	Os = require('os'),
	Fs = require('fs'),
	Handlebars = require('handlebars'),
	Shell = require('shelljs'),
	Process = require('./process'),
	Server = require('./server'),
	Worker = require('./worker'),
	Http = require('./http'),
	Opts = require('./opts'),
	log = $.logger("[herd]"),
	Herd = module.exports = function Herd(opts) {
		var self = $.extend(this, Herd.defaults(opts));

		self.servers = spawnAll(self.servers, Server)
		self.workers = spawnAll(self.workers, Worker)

		self.shepherdId = [Os.hostname(), self.admin.port].join(":")

		// connect to rabbitmq
		rabbitConnect(self)
		// connect our web routes
		webConnect(self)
		// register our process signal handlers
		signalHandlers(self)

	} // end constructor Herd


// make sure a herd object has all the default stuff
Herd.defaults = function(opts) {

	opts = $.extend(Object.create(null), opts)
	// the above has two effects: allows calling without arguments
	// and ensures that the opts object can't be polluted by Object.prototype

	if( 'exec' in opts ) {
		opts.server = opts.exec
	}

	if( $.is('object', opts.servers) ) {
		opts.servers = [ opts.servers ]
	}

	if( ! $.is('array', opts.servers) ) {
		opts.servers = [ { cd: ".", cmd: "echo invalid 'server' value in config json" } ]
	}

	opts.servers = $(opts.servers).map(function(server) {

		server = $.extend(Object.create(null), {
			cd: ".",
			cmd: "node index.js",
			count: Math.max(1, Os.cpus().length - 1),
			port: 8000, // a starting port, each child after the first will increment this
			portVariable: "PORT", // and set it in the env using this variable
			env: {}
		}, server)

		try
			server.port = parseInt(server.port, 10)
		catch Error
			server.cmd = "echo invalid 'port' value in config json: " + server.port
			server.port = 8001

		try
			server.count = parseInt(server.count, 10)
		catch Error
			server.cmd = "echo invalid 'count' value in config json: " + server.count
			server.count = 1

		if( server.count < 0 ) {
			server.count += Os.cpus().length
		}

		// control what happens at (re)start time
		server.restart = $.extend(Object.create(null), {
			maxAttempts: 5, // failing five times fast is fatal
			maxInterval: 10000, // in what interval is "fast"?
			gracePeriod: 3000, // how long to wait for a forcibly killed process to die
			timeout: 10000, // how long to wait for a newly launched process to start listening on it's port
		}, server.restart)

		server.git = $.extend(Object.create(null), {
			remote: "origin",
			branch: "master",
			command: "git pull {{remote}} {{branch}} || git merge --abort"
		}, server.git)

		server.git.command = Handlebars.compile(server.git.command)
		server.git.command.inspect = function(level) {
			return '"' + server.git.command({ remote: "{{remote}}", branch: "{{branch}}" }) + '"'
		}

		return server
	})


	opts.rabbitmq = $.extend(Object.create(null), {
		enabled: true,
		url: "amqp://localhost:5672",
		exchange: "shepherd"
	}, opts.rabbitmq)

	switch(Os.platform()) {
		case 'darwin':
			opts.nginx = $.extend(Object.create(null), {
				config: "/usr/local/etc/nginx/conf.d/shepherd_pool.conf",
				reload: "launchctl stop homebrew.mxcl.nginx && launchctl start homebrew.mxcl.nginx" // only used if nginx.config is set to a writeable filename
			}, opts.nginx)
			break;
		case 'linux':
			opts.nginx = $.extend(Object.create(null), {
				config: "/etc/nginx/conf.d/shepherd_pool.conf",
				reload: "/etc/init.d/nginx reload" // only used if nginx.config is set to a writeable filename
			}, opts.nginx)
			break;
		default:
			opts.nginx = $.extend(Object.create(null), {
				config: null,
				reload: "echo"
			}, opts.nginx)
			log("Unknown platform:", Os.platform(), "nginx configuration defaults will be meaningless.")
	}

	opts.admin = $.extend(Object.create(null), { // the http server listens for REST calls and webhooks
		port: 9000
	}, opts.admin)

	// "worker" can be set in the config json
	// but it just morphs into the "workers" array with one item in it
	if( $.is('object', opts.worker) ) {
		opts.workers = [ opts.worker ]
		delete opts.worker
	}
	// and then "worker" becomes read-only (see: "workers" array)
	$.defineProperty(opts, "worker", {
		get: function() {
			return opts.workers[0]
		}
	})

	if( ! $.is('array', opts.workers) ) {
		opts.workers = []
	}

	opts.workers = $(opts.workers).map(function(w) {
		return $.extend(Object.create(null), {
			count: 1,
			cd: ".",
			cmd: "echo No worker cmd specified"
		}, w);
	})

	if( Opts.verbose ) log("Using configuration:", require('util').inspect(opts))

	return opts;
}

Herd.prototype.checkConflict = function() {
	var self = this, i = 0, j = 0, ranges = $();
	for( i = 0; i < self.servers.length; i++ ) {
		ranges.push([
			self.servers[i].port,
			self.servers[i].port + self.servers[i].count - 1
		])
	}
	ranges.each(function(rangeA) {
		ranges.each(function(rangeB) {
			// TODO: check for range overlaps
		})
	})
}

Herd.prototype.listen = function() {
	var self = this,
		p = $.Promise();
	Process.findOne({ ports: self.admin.port }).then(function(owner) {
		if( owner != null ) {
			log("Killing old listener on admin port ("+self.admin.port+"): "+owner.pid)
			owner.kill("SIGKILL").then(function() {
				Http.listen(self.admin.port)
			})
		} else {
			Http.listen(self.admin.port)
		}
}

Herd.prototype.setStatus = function(status) {
	var self = this;
	self.rabbitmq.publish({ op: "status", status: status, from: self.shepherdId })
}

Herd.prototype.update = function() {
	var self = this,
		p = $.Promise(),
		done = {};
	$(self.servers).each(function(server) {
		var cmd = 'bash -c "cd ' + server.cd + ' && ' + server.git.command(server.git) + '"';
		// only process git pull commands in each unique directory
		if( server.cd in done )
			return;
		done[server.cd] = 1
		Process.exec(cmd).then(function(output) {
			self.rollingRestart()
			p.resolve(output);
		}, p.reject);
	})
}

Herd.prototype.workerRestart = function() {
	var self = this;
	$(self.workers).each(function(worker) {
		if( worker.process != null ) {
			log("Killing old worker:", worker.process.pid)
			Process.find({ ppid: worker.process.pid }).then(function(procs) {
				var pids = $(procs).select('pid').join(" ");
				log("Killing all worker children:", pids);
				Shell.exec("kill -15 " + pids);
			})
		} else {
			log("Launching new worker...")
			worker.spawn()
		}
	})
}

Herd.prototype.rollingRestart = function(from, done) {
	var self = this,
		from = from || 0,
		next = from + 1,
		done = done || $.Promise(),
		fail = function(msg) {
			done.reject(msg)
		}
	if( Opts.verbose ) log("Rolling restart:", from)
	try {
		if( from < 0 ) {
			fail('invalid index')
		} else if( from >= self.servers.length ) {
			done.resolve()
		} else if( self.servers[from] == null ) {
			fail('invalid child index: '+from)
		} else if( self.servers[from].process == null ) {
			self.servers[from].spawn().wait(function(err) {
				if( err != null ) return fail(err)
				self.rollingRestart(next, done)
			})
		} else {
			self.servers[from].kill().wait(self.restart.gracePeriod, function(err) {
				if( err != null ) return fail(err)
				self.servers[from].started.wait(function(err) {
					if( err != null ) return fail(err)
					self.rollingRestart(next, done)
				})
			})
		}
	} catch (_err) {
		fail(_err)
	}
	return done;
}

var signals = {
	SIGKILL: 9,
	SIGTERM: 15,
	SIGINT: 2,
	SIGHUP: 1,
}

function spawnAll(stuff, klass) {
	var i = 0, j = 0;
	return $(stuff).map(function(thing) {
		log("Spawning", thing.count, klass.name + "s")
		var a = [];
		for( j = 0; j < server.count; j++) {
			a.unshift( new klass(self, i++) )
			a[0].spawn()
		}
		return a
	}).flatten()
}

function killAll(stuff, signal) {
	if( stuff.length == 0 ) return $.Promise().resolve()
	var p = $.Progress(stuff.length);
	$(stuff).each(function(thing) {
		if( thing && thing.process ) {
			Process.tree(thing.process).then(function(tree) {
				Process.walk(tree, function(proc) {
					p.include(proc.kill(signal))
				})
				thing.process = null
				p.finish(1)
			})
		}
	})
	return p;
}

function signalHandlers(self) {

	// on SIGINT or SIGTERM, kill everything and die
	["SIGINT", "SIGTERM"].forEach(function(sig) {
		process.on(sig, function() {
			self.killAll("SIGKILL").then(function() {
				process.exit(0);
			}, function(err) {
				console.log(err);
				process.exit(1);
			})
		})
	});

	// on SIGHUP, just reload all child procs
	process.on("SIGHUP", function() {
		self.rollingRestart()
		self.workerRestart()
	});
}

function webConnect(self) {

	// a macro for registering a route (handled by lib/http.js)
	function webRoute(method, url, handler) { $.publish("http-route", method, url, handler) }

	// a macro for a plain-text request handler
	function plain(f) {
		return function(req, res) {
			res.contentType = "text/plain";
			res.send = function(status, content, enc) {
				enc = enc || 'utf8';
				res.statusCode = status;
				res.end(content, enc);
			}
			return f(req, res);
		}
	}

	// Worker status via REST
	webRoute("get", "/workers", plain(function(req, res) {
		res.send(200, $.toString(self.getWorkerStatus()))
	}))
	// Worker restart via REST
	webRoute("get", "/workers/restart", plain(function(req, res) {
		self.workerRestart()
		res.redirect(302, "/workers")
	}))

	// Server status via REST
	webRoute("get", "/servers", plain(function(req, res) {
		self.getServerStatus().then(function(list) {
			res.send(200, JSON.stringify(list))
		}, function(err) {
			res.send(500, JSON.stringify(err.stack));
		})
	}))

	// Server restart via REST
	webRoute("get", "/servers/restart", plain(function(req, res) {
		self.rollingRestart()
		res.redirect(302, "/servers")
	}))

	// Restart a single child process via REST
	webRoute("get", "/servers/restart/:index", plain(function(req, res) {
		var index = parseInt(req.params.index, 10),
			server = self.servers[index],
			fail = function(err) {
				if( err && 'stack' in err ) res.send(500, err.stack)
				else res.send(500, JSON.stringify(err))
			}
			finish = function(text) {
				res.send(200, text)
			}

		if( server == null ) return fail("No such server.")

		server.kill().wait(self.restart.gracePeriod, function(err) {
			if( err != null ) return fail(err)
			else finish("Server "+index+" killed, now it should auto-restart.")
		})
	}))

	// Update all via REST
	var webUpdate = plain(function(req, res) {
		self.update().then(function(output) {
			res.send(200, output)
		}, function(err) {
			res.send(500, JSON.stringify(err));
		})
	})
	webRoute("get", "/update", webUpdate)
	webRoute("post", "/update", webUpdate) // listen for POST too, to make webhook support trivial

	// publish an "update" message to everyone over rabbitMQ
	var webBroadcast = plain(function(req, res) {
		try {
			self.rabbitmq.publish({ op: "update" }) // tell everyone to update (including ourself)
			res.send(200, "Broadcast sent.")
		} catch( err ) {
			res.send(500, err.stack || String(err))
		}
	})
	webRoute("get", "/broadcast-update", webBroadcast)
	webRoute("post", "/broadcast-update", webBroadcast)

}

function rabbitConnect(self) {
	if( self.rabbitmq.enabled && self.rabbitmq.url != null && self.rabbitmq.url != '') {
		require('./amqp').connect(self.rabbitmq.url).wait(function(err, context) {
			if( err ) {
				log("Failed to connect to rabbitmq at:", self.rabbitmq.url, "error:")
				log(err.stack)
				self.rabbitmq.publish = self.rabbitmq.subscribe = $.identity;
			} else {
				self.rabbitmq.context = context;
				self.rabbitmq.publish = function(message) {
					var pub = self.rabbitmq.context.socket("PUB")
					pub.connect(self.rabbitmq.exchange, function() {
						pub.end(JSON.stringify(message), 'utf8')
					})
				}
				self.rabbitmq.subscribe = function(handler) {
					var sub = self.rabbitmq.context.socket("SUB")
					sub.connect(self.rabbitmq.exchange, function() {
						var on_data = function(data) {
							handler(JSON.parse(String(data)))
						}
						sub.on('data', on_data)
						sub.on('drain', on_drain)
					})
				}
				// broadcast that we are online
				self.rabbitmq.publish({ op: "status", status: "online", from: self.shepherdId })
			}
		})
	} else {
		self.rabbitmq.publish = self.rabbitmq.subscribe = $.identity;
	}

	// hook up a broadcaster to announce our demise
	["exit", "SIGINT", "SIGTERM"].forEach(function(sig) {
		process.on(sig, function() {
			log("Got signal:", sig)
			self.rabbitmq.publish({ op: "status", status: "offline", from: self.shepherdId, signal: sig })
		})
	});

	function rabbitRoute(pattern, handler) { $.publish("amqp-route", self.rabbitmq.exchange, pattern, handler) }
	// Restart all via AMQP message:
	rabbitRoute({ to: self.shepherdId, op: "restart" }, function (msg) { self.rollingRestart() })
	// Update (git) via AMQP message:
	rabbitRoute({ op: "update" }, function (msg) { self.update() })
	// Response to a status query via AMQP message:
	rabbitRoute({ op: "ping" }, function (msg) {
		if( ! 'ts' in msg )
			return log("Malformed PING message from rabbitmq:", msg)
		self.getServerStatus().then(function(status) {
			self.rabbitmq.publish({ op: "pong",
				ts: $.now, dt: $.now - msg.ts,
				from: self.shepherdId,
				status: { servers: status, workers: self.getWorkerStatus() }
			})
		})
	})

}

Herd.prototype.killAll = function(signal) {
	var p = $.Progress(1)
	p.include(killAll(this.servers, signal));
	p.include(killAll(this.workers, signal));
	return p.finish(1)
}

function getPoolConfig(self) {
	var seen = Object.create(null),
		s = "";
	if( self.servers.length > 0 ) {
		$(self.servers).each(function(server) {
			if( !(server.pool_name in seen) ) {
				if( s.length > 0 ) s += "}\n";
				s += "upstream " + server.pool_name + " {\n"
				seen[server.pool_name] = 1
			}
			s += "\tserver 127.0.0.1:" + server.port + ";\n"
		})
		s += "}"
	}
	return s;
}

Herd.prototype.writeConfig = function(fail_timeout) {
	var self = this,
		pool_string = getPoolConfig(self)
	if( self.nginx.config != null ) {
		log("Writing nginx configuration to file:", self.nginx.config)
		Fs.writeFile(self.nginx.config, pool_string, function(err) {
			if( err != null ) log("Failed to write nginx config file:", err)
			else {
				log(self.nginx.reload)
				Process.exec(self.nginx.reload).wait(function(err) {
					if( err != null ) log("Failed to reload nginx:", err)
				})
			}
		})
	}
}

Herd.prototype.getWorkerStatus = function() {
	return $(this.workers).map(function(w) {
		if( w.process && w.process.pid ) {
			return w.process.pid
		} else {
			return "DEAD"
		}
	}).toArray()
}

Herd.prototype.getServerStatus = function() {
	var self = this, p = $.Promise();
	log("Getting status...")
	$.Promise.collect($(self.servers).select('getResources').call()).wait(function(err, list) {
		if( err != null ) return p.reject(err)
		var i = 0, pid, port, cpu;
		for( ; i < list.length; i++) {
			port = self.servers[i].port
			if( self.servers[i].process != null ) {
				pid = self.servers[i].serverPid
			} else {
				pid = "DEAD"
			}
			cpu = list[i].split(' ')
				.map(function(x) { return parseFloat(x) })
			list[i] = [pid, port, cpu[0], cpu[1]]
		}
		log("Status:", list)
		p.resolve(list)
	})
	return p
}

