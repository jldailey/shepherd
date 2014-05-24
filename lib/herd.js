var $ = require('bling'),
	Os = require('os'),
	Handlebars = require('handlebars'),
	Child = require('./child'),
	log = $.logger("[herd]"),
	Herd = function Herd(opts) {
		var self = $.extend(this, Herd.defaults(opts)),
			webUpdate = null, pool = null, i = 0;
		self.children = new Array(self.count);
		for( ; i < self.children.length; i++) {
			self.children[i] = new Child(self, i)
		}

		self.shepherdId = [Os.hostname(), self.http.port].join(":")

		// connect to rabbitmq
		require('./amqp').connect(self.rabbitmq.url).then(function(context) {
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

			self.rabbitmq.publish({ op: "status", status: "online", from: self.shepherdId })

			["exit", "SIGINT", "SIGTERM"].forEach(function(sig) {
				process.on(sig, function() {
					self.rabbitmq.publish({ op: "status", status: "offline", from: self.shepherdId })
				})
			})

		})

		// Status via REST endpoint:
		$.publish("http-route", "get", "/children", function(req, res) {
			self.getStatus().wait(function(err, list) {
				res.contentType = "text/plain"
				if( err != null ) {
					res.statusCode = 500;
					res.end(JSON.stringify(err), 'utf8');
				} else {
					res.statusCode = 200;
					res.end(JSON.stringify(list), 'utf8')
				}
			})
		})

		// Restart all via REST endpoint:
		$.publish("http-route", "get", "/children/restart/all", function(req, res) {
			res.contentType = "text/plain"
			res.statusCode = 200;
			res.end("Restarting all...")
			self.rollingRestart()
		})

		// Restart a single child process via REST endpoint:
		$.publish("http-route", "get", "/children/restart/:index", function(req, res) {
			var index = parseInt(req.params.index, 10),
				child = self.children[index],
				fail = function(err) {
					res.contentType = "text/plain"
					res.statusCode = 200;
					res.end(JSON.stringify(err))
				},
				finish = function(html) {
					res.contentType = "text/plain"
					res.statusCode = 200;
					res.end(html)
				}

			if( child == null ) return fail("No such child.")

			child.kill().wait(self.restart.gracePeriod, function(err) {
				if( err != null ) return fail(err)
				else finish("Child "+index+" killed, now it should auto-restart.")
			})
		})

		// Update all via REST endpoint
		$.publish("http-route", "get", "/children/update", webUpdate = function(req, res) {
			self.update().wait(function(err, output) {
				res.contentType = "text/plain";
				if( err != null ) {
					res.statusCode = 500;
					res.end(JSON.stringify(err));
				} else {
					res.statusCode = 200;
					res.end(output)
				}
			})
		})
		$.publish("http-route", "post", "/children/update", webUpdate)

		// Restart all via AMQP message:
		$.publish("amqp-route", self.rabbitmq.exchange, { to: self.shepherdId, op: "restart", arg: "all" }, function (msg) {
			self.rollingRestart()
		})
		// Restart one via AMQP message:
		$.publish("amqp-route", self.rabbitmq.exchange, { to: self.shepherdId, op: "restart" }, function (msg) {
			try {
				index = parseInt(msg.arg, 10)
				var child = self.children[index]
				if( child == null ) log("invalid index from msg.arg", index)
				else child.kill()
			} catch(_err) {
				log("error:", _err, _err.stack)
			}
		})

		// Update via AMQP message:
		$.publish("amqp-route", self.rabbitmq.exchange, { op: "update" }, function (msg) {
			log("amqp-route: updating...")
			self.update()
		})

		// Response to a status query via AMQP message:
		$.publish("amqp-route", self.rabbitmq.exchange, { op: "ping" }, function (msg) {
			log("Got PING message...")
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
		count: Math.max(1, Os.cpus().length - 1),
		port: 8000,
		portVariable: "PORT"
	}, opts)

	opts.port = parseInt(opts.port, 10)
	opts.count = parseInt(opts.count, 10)

	opts.exec = $.extend({
		cd: ".",
		cmd: "node index.js"
	}, opts.exec)

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

	opts.nginx = $.extend({
		config: null,
		reload: "service nginx reload" // only used if .config is set to a writeable filename
	}, opts.nginx)

	opts.http = $.extend({ // the http server listens for REST calls and webhooks
		port: 9000
	}, opts.http)

	opts.env = $.extend({
	}, opts.env)

	return opts;
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
			log("fail:", msg, msg.stack)
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
				else self.rollingRestart(next, done)
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
				$.Promise.exec("bash -c '" + self.nginx.reload +"'").wait(function(err) {
					if( err != null ) log("Failed to reload nginx:", err)
					else log("Reloaded nginx")
				})
			}
		})
	}
}

Herd.prototype.getStatus = function() {
	var self = this, p = $.Promise();
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
		p.finish(list)
	})
	return p
}

