(function() {

	var $ = require("bling"),
		Shell = require("shelljs"),
		Fs = require("fs"),
		Opts = require("commander"),
		Http = require('http'),
		Os = require('os'),
		Helpers = require('./helpers'),
		Http = require('./http'),
		git = require('./git')

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
			console.log(Opts)
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
				command: "node app.js",
				count: Math.max(1, Os.cpus().length - 1),
				port: 8000
			}, herd)

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

		function makeEnvString(env, port) {
			var val, ret = "";
			for( key in env ) {
				val = env[key]
				if( val == null ) continue;
				ret += key + '="'+val+'" '
			}
			ret += Opts.portVariable + '="'+port+'" '
			return ret
		}

		function isDefined(x) {
			return x !== undefined;
		}

		function getPortOwner(port) {
			// returns the pid of the process listening on the port
			var p = $.Promise()
			$.Promise.exec("lsof -i :"+port+" | grep LISTEN | awk '{print \$2}'").wait(function(err, pid) {
				if(err != null) return p.fail(err)
				else try { return p.finish(parseInt(pid, 10))	}
				catch (parse_err) { return p.fail(parse_err) }
			})
			return p
		}

		function getChildOf(pid) {
			var p = $.Promise()
			$.Promise.exec("ps axj | grep '\\<"+pid+"\\>' | grep -v grep | awk '{print \$3}' ").then(function(output) {
				try { p.finish(parseInt(output, 10)) }
				catch (err) { p.fail(err) }
			})
			return p
		}

		function waitUntilPortIsOwned(pid, port, timeout) { // by the pid or a pid who is a child of this pid
			var p = $.Promise(),
				started = $.now,
				wait_once = function() {
					if( $.now - started > timeout ) {
						return fail("Waiting failed after a timeout of: " + timeout + "ms")
					}
					getPortOwner(port).wait(function (err, owner) {
						if( err != null ) return p.fail(err)
						if( pid == owner ) return p.finish(owner)
						getChildOf(owner).wait(function (err, child) {
							if( err != null ) return p.fail(err)
							if( pid == child ) return p.finish(owner)
							else setTimeout(wait_once, 300)
						})
					})
				}
			wait_once()
			p.then(function(owner) {
				log("Port",port,"is owned by",owner)
			})
			return p;
		}

		function Child(herd, command, port, index) {
			this.herd = herd;
			this.command = command;
			this.index = index || 0;
			this.port = port + index;
			this.process = null;
			this.startAttempts = 0;
			this.startReset = null;
			this.log = $.logger("child[:"+this.port+"]")
			Child.count += 1;
		}

		Child.count = 0;

		Child.prototype.spawn = function(env, started) {
			var self = this,
				started = started || $.Promise(),
				env_string = makeEnvString(self.env, self.port)
			getPortOwner(self.port).then(function(owner) {
				// if the port is being listened on
				if( owner != null && isFinite(owner) ) {
					self.log("Killing previous owner of", self.port, "PID:", owner)
					// kill the other listener (probably it's an old version of ourself)
					process.kill(owner)
					// give it a grace period to release the port before we try to re-spawn
					$.delay(self.herd.restart.gracePeriod, function() {
						self.spawn(env, started)
					})
					return started;
				}
				self.process = Shell.exec(env_string + "bash -c '" + self.command + "'", { silent: true, async: true }, $.identity)
				self.process.on("exit", function(err, code) { self.onExit(code) })
				self.process.stdout.on("data", function(data){
					data = data.replace(/\n/,'')
					self.log(data);
				})
				self.process.stderr.on("data", function(data){
					data = data.replace(/\n/g,'')
					self.log("(stderr)", data)
				})
				waitUntilPortIsOwned(self.process.pid, self.port, self.herd.restart.timeout).wait(function(err, owner) {
					if( err != null) started.fail(err)
					else {
						self.serverPid = owner
						started.finish(owner)
					}
				})
			})
			return started;
		}

		Child.prototype.kill = function(signal) {
			var self = this,
				p = $.Promise()
			if( self.process == null ) return p.fail('no process')
			self.process.on('exit', function(exitCode) {
				p.finish(exitCode)
			})
			self.process.kill(signal)
			return p
		}

		Child.prototype.onExit = function(exitCode) {
			var self = this;
			if( self.process == null ) {
				return;
			}
			Child.count -= 1
			log("Child PID: " + self.process.pid + " Exited with code: ", exitCode);
			// Record the death of the child
			self.process = null;
			// if it died with a restartable exit code, attempt to restart it
			if ( self.startAttempts < self.herd.restart.maxAttempts ) {
				self.startAttempts += 1;
				// schedule the forgetting of start attempts
				clearTimeout(self.startReset);
				self.startReset = setTimeout( function() {
					self.startAttempts = 0;
				}, self.herd.restart.maxInterval)
				// attempt a restart
				self.spawn(self.env);
			}
		}
		
		Child.prototype.toString = function() {
			return "Child[:"+this.port+"]"
		}

		Child.prototype.getResources = function() {
			var self = this
			return $.Promise.exec("ps auxww | grep '\\<"+self.serverPid+"\\>' | grep -v grep | awk '{print \$3, \$4}'")
		}

		function Herd(herd) {
			var i, self = $.extend( this, sanitizeHerd(herd) )
			self.children = new Array(self.count);
			for( i = 0; i < self.children.length; i++) {
				self.children[i] = new Child(self, self.command, self.port, i)
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
		} // end function Herd

		Herd.prototype.rollingRestart = function(from, done) {
			var self = this,
				from = from || 0,
				done = done || $.Promise(),
				fail = function(msg) {
					log("fail:", msg)
					done.fail(msg)
				}
			if( from < 0 ) {
				fail('invalid index')
			} else if( from >= self.children.length ) {
				done.finish()
			} else if( self.children[from] == null ) {
				fail('invalid child, index: '+from)
			} else if( self.children[from].process == null ) {
				self.children[from].spawn(self.env).wait(function(err) {
					if( err != null ) return fail(err)
					else self.rollingRestart(from + 1, done)
				})
			} else {
				log("Killing old process...")
				self.children[from].kill().wait(self.restart.gracePeriod, function(err) {
					if( err != null ) return fail(err)
					else self.children[from].spawn(self.env).wait(function (err) {
						if( err != null ) return fail(err)
						else self.rollingRestart(from + 1, done)
					})
				})
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
			herd.rollingRestart().then(function() {
				// start the admin server
				Http.listen(herd.http.port)
			})

		})
	})
}).call(this)
