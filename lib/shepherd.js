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

		function makeEnvString(env) {
			var val, ret = "";
			for( key in env ) {
				val = env[key]
				if( val == null ) continue;
				ret += key + '="'+val+'" '
			}
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

		function getParentOf(childPid) {
			var p = $.Promise()
			$.Promise.exec("ps axj | grep "+childPid+ " | grep -v grep | awk '{print \$3}' ").then(function(output) {
				try { p.finish(parseInt(output, 10)) }
				catch (err) { p.fail(err) }
			})
			return p
		}

		function waitUntilPortIsOwned(pid, port, timeout) {
			log("Waiting for pid:", pid, "to own port:", port)
			var p = $.Promise(),
				started = $.now,
				waiter = $.interval(300, function() {
					log("Waiting for pid:", pid, "to own port:", port)
					if( $.now - started > timeout ) {
						return fail("Waiting failed after a timeout of: " + timeout + "ms")
					}
					getPortOwner(port).wait(function(err, owner) {
						if( err != null ) return fail(err)
						if( pid == owner ) return finish("Port "+port+" is owned.")
						getParentOf(owner).wait(function(err, parent) {
							if( err != null ) return fail(err)
							if( pid == parent ) return finish("Port is owned by a child.")
						})
					})
				})
			function fail(err) {
				waiter.cancel()
				return p.fail(err)
			}
			function finish(msg) {
				if( msg != null ) log(msg);
				waiter.cancel();
				return p.finish()
			}
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
				env_string = makeEnvString($.extend(env, { PORT: self.port }))
			self.log("Checking if PORT "+self.port+" is owned.")
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
				self.log("Executing command to launch child...")
				self.process = Shell.exec(env_string + "bash -c '" + self.command + "'", { silent: true, async: true }, function(exitCode) {
					self.onExit(exitCode)
				}),
				self.process.stdout.on("data", self.log);
				self.process.stderr.on("data", function(data){ self.log("(stderr)", data) })
				self.log("Waiting for port to be owned")
				waitUntilPortIsOwned(self.process.pid, self.port, self.herd.restart.timeout).wait(function(err) {
					if( err != null) started.fail(err)
					else started.finish(self.process.pid)
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
			if (exitCode === self.herd.restart.exitCode && self.startAttempts < self.herd.restart.maxAttempts ) {
				self.startAttempts += 1;
				// schedule the forgetting of start attempts
				clearTimeout(self.startReset);
				self.startReset = setTimeout( function() {
					self.startAttempts = 0;
				}, self.herd.restart.maxInterval)
				// attempt a restart
				self.spawn();
			}
		}
		
		Child.prototype.toString = function() {
			return "Child[:"+this.port+"]"
		}

		function Herd(herd) {
			var i, self = $.extend( this, sanitizeHerd(herd) )
			self.children = new Array(self.count);
			try {
			for( i = 0; i < self.children.length; i++) {
				self.children[i] = new Child(self, self.command, self.port, i)
			}
			log("Child count: ", self.children.length)
			log("Child ports: ", $(self.children).select('port'))
			} catch (err) { console.log(err); process.exit(1) }

			$.publish("http-route", "get", "/children", function(req, res) {
				res.contentType = "text/plain"
				res.statusCode = 200;
				res.end(JSON.stringify($(self.children).select('process.pid').toArray()))
			})
		}

		Herd.prototype.rollingRestart = function(from, done) {
			var self = this,
				from = from || 0,
				done = done || $.Promise(),
				fail = function(msg) {
					log("fail:", msg)
					done.fail(msg)
				}
			log("Rolling restart:", from)
			if( from < 0 ) {
				fail('invalid index')
			} else if( from >= self.children.length ) {
				done.finish()
			} else if( self.children[from] == null ) {
				fail('invalid child, index: '+from)
			} else if( self.children[from].process == null ) {
				log("Spawning new process...")
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
