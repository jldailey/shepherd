(function() {

	var $ = require("bling"),
		Shell = require("shelljs"),
		Fs = require("fs"),
		Opts = require("commander"),
		Http = require('http'),
		Os = require('os'),
		Helpers = require('./helpers'),
		Http = require('./http'),
		Git = require('./git')
		Child = require('./child')

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
			var i, self = $.extend( this, sanitizeHerd(herd) )
			self.children = new Array(self.count);
			for( i = 0; i < self.children.length; i++) {
				self.children[i] = new Child(self, i)
			}
			log("Child ports: ", $(self.children).select('port'))

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
						list[i] = ["", port, pid, cpu]
					}
					res.contentType = "text/html"
					res.statusCode = 200;
					res.end("<table>"
						+ "<tr><th>Port<th>PID<th>CPU MEM</tr>"
						+ list.map(function(item) {
							return "<tr>" + item.join("<td>") + "</tr>"
						}).join("")
						+ "</table>"
					)
				})
			})

			$.publish("http-route", "get", "/children/restart/all", function(req, res) {
				var fail = function(err) {
						res.contentType = "text/plain"
						res.statusCode = 200;
						res.end(JSON.stringify(err))
					},
					finish = function(html) {
						res.contentType = "text/html"
						res.statusCode = 200;
						res.end(html)
					}
				self.rollingRestart().then(finish, fail)
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
						res.contentType = "text/html"
						res.statusCode = 200;
						res.end(html)
					}

				if( child == null ) return fail("No such child.")

				child.kill().wait(self.restart.gracePeriod, function(err) {
					if( err != null ) return fail(err)
					else finish("Killed, now it should auto-restart.")
				})
			})

			$.publish("http-route", "get", "/children/update", function(req, res) {
				var child = $(self.children).coalesce(),
					fail = function (err) {
						res.contentType = "text/plain";
						res.statusCode = 200;
						res.end(JSON.stringify(err));
					},
					finish = function(html) {
						res.contentType = "text/html";
						res.statusCode = 200;
						res.end(html);
					},
					cmd = 'bash -c "cd ' + child.path + ' && git pull || git merge --abort"'

				if( child == null ) return fail("No children to update")

				$.Promise.exec(cmd).wait(function(err, output) {
					if( err != null ) return fail(err)
					finish(output.replace(/(?:\r|\n)/g,'<br>'))
					self.rollingRestart()
				})
			})

		} // end function Herd

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
