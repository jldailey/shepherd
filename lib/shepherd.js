(function() {

	var $ = require("bling"),
		Shell = require("shelljs"),
		Fs = require("fs"),
		Opts = require("commander"),
		Os = require('os'),
		Helpers = require('./helpers'),
		Http = require('./http'),
		Git = require('./git')
		Child = require('./child'),
		Amqp = require('./amqp')

	log = $.logger("[shepherd]");

	// Read our own package.json
	$.Promise.jsonFile(__dirname + "/../package.json").then(function(pkg) {

		// Parse command-line options
		Opts.version(pkg.version)
			.option('-f [file]', "The .herd file to load", ".herd")
			.option('-o [file]', "Where to send log output", "-")
			.option('-p, --port-variable [string]', 'Which environment variable to set the port in.', 'PORT')
			.option('--nginx', "Output an nginx configuration based on the herd file")
			.option('--defaults', "Output a complete herd file with all defaults")
			.parse(process.argv);

		if( Opts.defaults ) {
			console.log(sanitizeHerd({}))
			process.exit(0)
		}

		if( Opts.nginx ) {
			console.log("TODO: output an nginx configuration for this herd")
			process.exit(0)
		}

		if( Opts.O != "-" ) {
			(function() {
				try {
					var fileName = Opts.O,
						outStream = Fs.createWriteStream(fileName, { flags: 'a', mode: 0666, encoding: 'utf8' })
				} catch( err ) {
					console.error("Failed to establish output stream to "+fileName)
					console.error(err)
					return;
				}
				$.log.out = function(msg) {
					try {
						outStream.write(msg, 'utf8')
					} catch( err ) {
						console.error("Failed to write to "+fileName)
						console.error(err)
					}
				}
			})()
		}

		// make sure a herd object has all the default stuff
		function sanitizeHerd(herd) {
			herd = $.extend({
				count: Math.max(1, Os.cpus().length - 1),
				port: 8000,
				portVariable: "PORT"
			}, herd)

			herd.exec = $.extend({
				cd: ".",
				cmd: "node index.js"
			}, herd.exec)

			herd.restart = $.extend({
				code: 1, // process exit code that causes an immediate restart
				maxAttempts: 5, // failing five times fast is fatal
				maxInterval: 10000,
				gracePeriod: 3000, // how long to wait for a forcibly killed process to die
				timeout: 10000, // how long to wait for a newly launched process to start listening on it's port
			}, herd.restart)

			herd.git = $.extend({
				remote: "origin",
				branch: "master",
			}, herd.git)

			herd.rabbitmq = $.extend({
				url: "amqp://localhost:5672",
				exchange: "shepherd"
			}, herd.rabbitmq)

			herd.http = $.extend({
				port: 9000
			}, herd.http)

			herd.env = $.extend({
			}, herd.env)

			return herd;
		}


		function Herd(herd) {
			var self = $.extend( this, sanitizeHerd(herd) ),
				i = 0;
			self.children = new Array(self.count);
			for( ; i < self.children.length; i++) {
				self.children[i] = new Child(self, i)
			}
			log("Child ports: ", $(self.children).select('port'))

			try { Amqp.connect(self.rabbitmq.url).wait(function(err, ok) {
				if( err != null ) return log("failed to connect to:", self.rabbitmq.url, err)
				else log("Connected to rabbitmq")
			}) } catch( _err ) {
				log(_err)
			}

			$.publish("http-route", "get", "/children", function(req, res) {
				$.Promise.collect($(self.children).select('getResources').call()).then(function(list) {
					var i = 0,
						pid, port, cpu;
					for( ; i < list.length; i++) {
						port = self.children[i].port
						if( self.children[i].process != null ) {
							pid = self.children[i].serverPid
						} else {
							pid = "DEAD"
						}
						cpu = list[i]
						list[i] = [pid, port, cpu]
					}
					res.contentType = "text/plain"
					res.statusCode = 200;
					res.end(JSON.stringify(list), 'utf8')
				})
			})

			$.publish("http-route", "get", "/children/restart/all", function(req, res) {
				res.contentType = "text/plain"
				res.statusCode = 200;
				res.end("Restarting all...")
				self.rollingRestart()
			})

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

			$.publish("amqp-route", self.rabbitmq.exchange, { op: "restart" }, function (msg) {
				log("amqp-route: restarting...")
				if( msg.arg == "all" ) {
					self.rollingRestart()
				} else try {
					index = parseInt(msg.arg, 10)
					var child = self.children[index]
					if( child == null ) log("invalid index from msg.arg", index)
					else child.kill()
				} catch(_err) {
					log("error:", _err, _err.stack)
				}
			})

			$.publish("http-route", "get", "/children/update", function(req, res) {
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
			$.publish("amqp-route", self.rabbitmq.exchange, { op: "update" }, function (msg) {
				log("amqp-route: updating...")
				self.update()
			})


		} // end function Herd

		Herd.prototype.update = function() {
			var self = this,
				child = $(self.children).coalesce(),
				p = $.Promise(),
				cmd = 'bash -c "cd ' + self.exec.cd + ' && git pull ' + self.git.remote + ' ' + self.git.branch + ' || git merge --abort"'

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

		Herd.prototype.killAll = function(signal, from, done) {
			var self = this,
				from = from || 0,
				done = done || $.Promise()
			if( from < 0 ) {
				return done.fail('invalid index')
			}
			if( from >= self.children.length ) {
				return done.finish()
			}
			if( self.children[from] == null ) {
				return done.fail('invalid child (index: '+from)
			}
			if( self.children[from].process == null ) {
				return self.killAll(signal, from + 1, done)
			}
			children[from].kill(signal).wait(function(err) {
				self.killAll(signal, from + 1, done)
			})
			return done;
		}

		$.Promise.jsonFile(Opts.F).then(function(herd) {
			herd = new Herd(herd)
			log("Starting new herd, shepherd PID: " + process.pid)

			// start all the processes
			herd.rollingRestart().wait(function(err) {
				if( err != null ) return log(err)
				// start the admin server
				Http.listen(herd.http.port)
			})
		})
	})
}).call(this)
