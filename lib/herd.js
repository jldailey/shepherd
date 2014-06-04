var $ = require('bling'),
	Os = require('os'),
	Fs = require('fs'),
	Handlebars = require('handlebars'),
	Child = require('./child'),
	log = $.logger("[herd]"),
	Http = require('./http'),
	Opts = require('./opts'),
	Herd = function Herd(opts) {
		var self = $.extend(this, Herd.defaults(opts)),
			webUpdate = null, pool = null, i = 0;
		self.children = new Array(self.exec.count);
		for( ; i < self.children.length; i++) {
			self.children[i] = new Child(self, i)
		}

		self.shepherdId = [Os.hostname(), self.admin.port].join(":")

		// connect to rabbitmq
		if( self.rabbitmq.url != null && self.rabbitmq.url != '') {
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
				self.rabbitmq.publish({ op: "status", status: "offline", from: self.shepherdId, signal: sig })
				log("Exiting from signal:", sig)
				if( sig != "exit" ) {
					process.exit( 1 );
				}
			})
		})

		function webRoute(method, url, handler) { $.publish("http-route", method, url, handler) }
		function rabbitRoute(pattern, handler) { $.publish("amqp-route", self.rabbitmq.exchange, pattern, handler) }

		function plain(f) {
			return function(req, res) {
				res.contentType = "text/plain";
				return f(req, res);
			}
		}

		// Status via REST endpoint:
		webRoute("get", "/children", plain(function(req, res) {
			self.getStatus().wait(function(err, list) {
				if( err != null ) {
					res.send(500, JSON.stringify(err), 'utf8');
				} else {
					res.send(200, JSON.stringify(list), 'utf8')
				}
			})
		}))

		// Restart all via REST endpoint:
		webRoute("get", "/children/restart/all", plain(function(req, res) {
			res.send(200, "Restarting all...")
			self.rollingRestart()
		}))

		// Restart a single child process via REST endpoint:
		webRoute("get", "/children/restart/:index", plain(function(req, res) {
			var index = parseInt(req.params.index, 10),
				child = self.children[index],
				fail = function(err) {
					if( err && 'stack' in err ) res.send(500, err.stack)
					else res.send(500, JSON.stringify(err))
				}
				finish = function(text) {
					res.send(200, text)
				}

			if( child == null ) return fail("No such child.")

			child.kill().wait(self.restart.gracePeriod, function(err) {
				if( err != null ) return fail(err)
				else finish("Child "+index+" killed, now it should auto-restart.")
			})
		}))

		// Update all via REST endpoint
		var webUpdate = plain(function(req, res) {
			self.update().wait(function(err, output) {
				res.contentType = "text/plain";
				if( err != null ) {
					res.statusCode = 500;
					res.send(JSON.stringify(err));
				} else {
					res.statusCode = 200;
					res.send(output)
				}
			})
		})
		webRoute("get", "/children/update", webUpdate)
		// listen for POST too, to make webhook support trivial
		webRoute("post", "/children/update", webUpdate)

		// publish an "update" message to everyone over rabbitMQ
		var webBroadcast = plain(function(req, res) {
			try {
				self.rabbitmq.publish({ op: "update" }) // tell everyone to update (including ourself)
				res.send(200, "Broadcast sent.")
			} catch( err ) {
				res.send(500, err.stack)
			}
		})
		webRoute("get", "/children/broadcast-update", webBroadcast)
		webRoute("post", "/children/broadcast-update", webBroadcast)

		// Restart all via AMQP message:
		rabbitRoute({ to: self.shepherdId, op: "restart", arg: "all" }, function (msg) {
			self.rollingRestart()
		})

		// Restart one via AMQP message:
		rabbitRoute({ to: self.shepherdId, op: "restart" }, function (msg) {
			try {
				var index = parseInt(msg.arg, 10)
			} catch(err) {
				return log("Invalid arg in rabbitmq 'restart' message:", msg.arg)
			}
			var child = self.children[index]
			if( child == null ) log("No such child:", index)
			else child.kill()
		})

		// Update via AMQP message:
		rabbitRoute({ op: "update" }, function (msg) {
			self.update()
		})

		// Response to a status query via AMQP message:
		rabbitRoute({ op: "ping" }, function (msg) {
			self.getStatus().then(function(status) {
				var response = { op: "pong", ts: $.now, dt: $.now - msg.ts, from: self.shepherdId, status: status }
				log("Sending PONG message...", response)
				self.rabbitmq.publish(response)
			})
		})

	} // end constructor Herd

module.exports = Herd

// make sure a herd object has all the default stuff
Herd.defaults = function(opts) {

	opts = $.extend({
	}, opts)

	opts.exec = $.extend({
		cd: ".",
		cmd: "node index.js",
		count: Math.max(1, Os.cpus().length - 1),
		port: 8000, // a starting port, each child after the first will increment this
		portVariable: "PORT", // and set it in the env using this variable
		env: {}
	}, opts.exec)
	opts.exec.port = parseInt(opts.exec.port, 10)
	opts.exec.count = parseInt(opts.exec.count, 10)

	opts.restart = $.extend({
		maxAttempts: 5, // failing five times fast is fatal
		maxInterval: 10000, // in what interval is "fast"?
		gracePeriod: 3000, // how long to wait for a forcibly killed process to die
		timeout: 10000, // how long to wait for a newly launched process to start listening on it's port
	}, opts.restart)

	opts.git = $.extend({
		remote: "origin",
		branch: "master",
		command: "git pull {{remote}} {{branch}} || git merge --abort"
	}, opts.git)

	opts.git.command = Handlebars.compile(opts.git.command)
	opts.git.command.inspect = function(level) {
		return '"' + opts.git.command({ remote: "{{remote}}", branch: "{{branch}}" }) + '"'
	}

	opts.rabbitmq = $.extend({
		url: "amqp://localhost:5672",
		exchange: "shepherd"
	}, opts.rabbitmq)

	switch(Os.platform()) {
		case 'darwin':
			opts.nginx = $.extend({
				config: "/usr/local/etc/nginx/conf.d/shepherd_pool.conf",
				reload: "launchctl stop homebrew.mxcl.nginx && launchctl start homebrew.mxcl.nginx" // only used if nginx.config is set to a writeable filename
			}, opts.nginx)
			break;
		case 'linux':
			opts.nginx = $.extend({
				config: "/etc/nginx/conf.d/shepherd_pool.conf",
				reload: "/etc/init.d/nginx reload" // only used if nginx.config is set to a writeable filename
			}, opts.nginx)
			break;
		default:
			opts.nginx = $.extend({
				config: null,
				reload: "echo"
			}, opts.nginx)
			log("Unknown platform:", Os.platform(), "nginx configuration defaults will be meaningless.")
	}

	opts.admin = $.extend({ // the http server listens for REST calls and webhooks
		port: 9000
	}, opts.admin)

	
	if( Opts.verbose ) log("Using configuration:", util.inspect(opts))

	return opts;
}

Herd.prototype.listen = function() {
	Http.listen(this.admin.port)
}

Herd.prototype.setStatus = function(status) {
	self.rabbitmq.publish({ op: "status", status: status, from: self.shepherdId })
}

Herd.prototype.update = function() {
	var self = this,
		child = $(self.children).coalesce(),
		p = $.Promise(),
		cmd = 'bash -c "cd ' + self.exec.cd + ' && ' + self.git.command(self.git) + '"'

	if( child == null ) return fail("No children to update")

	$.Promise.exec(cmd).wait(function(err, output) {
		if( err != null ) return p.fail(err)
		p.finish(output)
		self.rollingRestart()
	})

	return p
}

Herd.prototype.rollingRestart = function(from, done) {
	var self = this,
		from = from || 0,
		next = from + 1,
		done = done || $.Promise(),
		fail = function(msg) {
			done.fail(msg)
		}
	try {
		if( from < 0 ) {
			fail('invalid index')
		} else if( from >= self.children.length ) {
			done.finish()
		} else if( self.children[from] == null ) {
			fail('invalid child index: '+from)
		} else if( self.children[from].process == null ) {
			self.children[from].spawn().wait(function(err) {
				if( err != null ) return fail(err)
				self.rollingRestart(next, done)
			})
		} else {
			log("Killing old process...")
			self.children[from].kill().wait(self.restart.gracePeriod, function(err) {
				if( err != null ) return fail(err)
				else self.children[from].started.wait(function(err) {
					if( err != null ) return fail(err)
					else self.rollingRestart(next, done)
				})
			})
		}
	} catch (_err) {
		fail(_err)
	}
	return done;
}

Herd.prototype.writeConfig = function(fail_timeout) {
	var pool, self = this,
		fail_timeout = fail_timeout || "10s";
	if( self.nginx.config != null ) {
		log("Writing nginx configuration to file:", self.nginx.config)
		pool = "upstream shepherd_pool {\n"
			+ self.children.map(function(child) {
				return "\tserver 127.0.0.1:"+child.port+" max_fails=1 fail_timeout="+fail_timeout+";\n"
			}).join('') + "}"
		Fs.writeFile(self.nginx.config, pool, function(err) {
			if( err != null ) log("Failed to write nginx config file:", err)
			else {
				log(self.nginx.reload)
				$.Promise.exec("bash -c '" + self.nginx.reload +"'").wait(function(err) {
					if( err != null ) log("Failed to reload nginx:", err)
				})
			}
		})
	}
}

Herd.prototype.getStatus = function() {
	var self = this, p = $.Promise();
	log("Getting status...")
	$.Promise.collect($(self.children).select('getResources').call()).wait(function(err, list) {
		if( err != null ) return p.fail(err)
		var i = 0, pid, port, cpu;
		for( ; i < list.length; i++) {
			port = self.children[i].port
			if( self.children[i].process != null ) {
				pid = self.children[i].serverPid
			} else {
				pid = "DEAD"
			}
			cpu = list[i].replace('\n','').split(' ')
			list[i] = [pid, port, cpu[0], cpu[1]]
		}
		log("Status:", list)
		p.finish(list)
	})
	return p
}

