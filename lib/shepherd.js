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
			console.log("TODO")
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

		function waitUntilPortIsOwned(pid, port, timeout) {
			var p = $.Promise(),
				started = $.now,
				waiter = $.interval(300, function() {
					log("Waiting for pid: "+pid+" to own port:" + port)
					if( $.now - started > timeout ) {
						return p.fail('timeout')
					}
					getPortOwner(port).wait(function(err, owner) {
						if( err != null ) return p.fail(err)
						if( owner == pid ) {
							log("Port "+port+" is owned.")
							waiter.cancel();
							p.finish();
						}
					})
				})
			return p;
		}

		function Child(command, port, index) {
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
				env_string = makeEnvString($.extend(env, { PORT: this.port }))
			getPortOwner(self.port).then(function(owner) {
				// if the port is being listened on
				if( owner != null && isFinite(owner) ) {
					// kill the other listener (probably it's an old version of ourself)
					process.kill(owner)
					// give it a grace period to release the port before we try to re-spawn
					$.delay(herd.restart.gracePeriod, function() {
						self.spawn(env, started)
					})
					return started;
				}
				self.process = Shell.exec(env_string + "bash -c '" + self.command + "'", { silent: true, async: true }, function(exitCode) {
					self.onExit(exitCode)
				}),
				self.process.stdout.on("data", self.log);
				self.process.stderr.on("data", function(data){ self.log("(stderr)", data) })
				waitUntilPortIsOwned(self.process.pid, self.port, herd.restart.timeout).wait(function(err) {
					if( err != null) started.fail(err)
					else started.finish(self.process.pid)
				})
			})
			return started;
		}

		Child.prototype.kill = function(signal) {
			var p = $.Promise()
			if( this.process == null ) return p.fail('no process')
			this.process.on('exit', function(exitCode) {
				p.finish(exitCode)
			})
			this.process.kill(signal)
			return p
		}

		Child.prototype.onExit = function(exitCode) {
			if( this.process == null ) {
				return;
			}
			Child.count -= 1
			log("Child PID: " + this.process.pid + " Exited with code: ", exitCode);
			// Record the death of the child
			this.process = null;
			// if it died with a restartable exit code, attempt to restart it
			if (exitCode === herd.restart.exitCode && this.startAttempts < herd.restart.maxAttempts ) {
				this.startAttempts += 1;
				// schedule the forgetting of start attempts
				clearTimeout(this.startReset);
				this.startReset = setTimeout( function() {
					this.startAttempts = 0;
				}, herd.restart.maxInterval)
				// attempt a restart
				this.spawn();
			}
		}
		
		Child.prototype.toString = function() {
			return "Child[:"+this.port+"]"
		}

		function Herd(herd) {
			var i, self = $.extend( this, sanitizeHerd(herd) )
			log("Herd:", self)

			self.children = new Array(self.count);
			try {
			for( i = 0; i < self.children.length; i++) {
				self.children[i] = new Child(self.command, self.port, i)
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
					if( err != null ) return done.fail(err)
					else self.rollingRestart(from + 1, done)
				})
			} else {
				log("Killing old process...")
				self.children[from].kill().wait(herd.restart.gracePeriod, function(err) {
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
