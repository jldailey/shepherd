(function() {

	var $ = require("bling"),
		Shell = require("shelljs"),
		Fs = require("fs"),
		Opts = require("commander"),
		Http = require('http'),
		Os = require('os'),
		Helpers = require('./helpers'),
		httpServer = require('./http'),
		git = require('./git')

	log = $.logger("[shepherd]");

	log("Starting as PID:", process.pid);

	// Read our own package.json
	$.Promise.jsonFile(__dirname + "/../package.json").then(function(pkg) {

		log("Parsed package.json...")

		// Parse command-line options
		Opts.version(pkg.version)
			.option('-f [file]', "The .herd file to load", ".herd")
			.parse(process.argv);

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
				delay: 1000 // how long to wait after a crash before restart
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

			log("Sanitized herd:", herd);

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

		$.Promise.jsonFile(Opts.F).then(function(herd) {
			try {
				var i,
					isDefined = function(x) { return x !== undefined },
					herd = sanitizeHerd(herd),
					maxChildren = 'count' in herd ? herd.count : Math.max(1, os.cpus().length - 1),
					children = new Array(maxChildren), // the list of child processes,
					startAttempts = 0, // use these to enforce herd.restart.maxAttempts
					restartTimeout = null,
					getPortOwner = function(port) {
						var p = $.Promise()
						$.Promise.exec("lsof -i :"+port+" | grep LISTEN | awk '{print \$2}'").wait(function(err, pid) {
							if(err != null) return p.fail(err)
							else return p.finish(parseInt(pid, 10))	
						})
						return p
					},
					handleExit = function(i, child, exitCode) {
						log("Child PID: " + child.pid + " Exited with code: ", exitCode);
						if( i > -1 && i < children.length ) {
							// Record the death of the child
							children[i] = undefined;
						} else {
							log("Warning: child index " + i + " (pid: "  + child.pid + ") not in range: 0.." + children.length)
						}
						// if it died with a restartable exit code, attempt to restart it
						if (exitCode === herd.restart.exitCode && startAttempts < herd.restart.maxAttempts ) {
							startAttempts += 1;
							// after a while, forget about previous start attempts
							clearTimeout(restartTimeout);
							restartTimeout = setTimeout( function() {
								startAttempts = 0;
							}, herd.restart.maxInterval)
							// restart the child
							launchOne(i);
						} else {
							// handle a clean exit by a child
							child_count = $(children).filter(isDefined).length 
							if (child_count === 0 ) {
								log("All children exited gracefully, shutting down (no flock to tend).");
								process.exit(0);
							} else {
								log("Still " + child_count + " children running");
							}
						}
					},
					waitForPidToListenOnPort = function(pid, port) {
						var p = $.Promise(),
							waiter = $.interval(1000, function() {
								log("Waiting for pid: "+pid+" to own port:" + port)
								getPortOwner(port).wait(function(err, owner) {
									if( err != null ) return p.fail(err)
									if( owner == pid ) {
										waiter.cancel();
										p.finish();
									}
								})
							})
						return p;
					},
					launchOne = module.exports.launchOne = function(i) { // launches a single child
						if( i < 0 || i >= children.length ) return $.Promise().fail("Invalid child index.");
						var started = $.Promise(),
							port = herd.port + i;
						getPortOwner(port).then(function(owner) {
							if( owner != null && isFinite(owner) ) {
								log("Killing other owner:", owner)
								process.kill(owner);
							}
							var	env_string = makeEnvString($.extend(herd.env, { PORT: port })),
								child = children[i] = Shell.exec(env_string + "bash -c '" + herd.command + "'", { silent: true, async: true }, function(exitCode) {
									handleExit(i, child, exitCode)
								}),
								child.port = port,
								child.log = $.logger("child[:"+port+"]"),
							child.stdout.on("data", child.log)
							child.stderr.on("data", function(data){ child.log("(stderr)", data) })
							waitForPidToListenOnPort(child.pid, child.port).wait(function(err, ok) {
								if( err != null ) { started.fail(err) }
								else { started.finish(ok) }
							})
						})
						return started;
					},

					reLaunchAll = module.exports.reLaunchAll = function() {
						log("relaunchAll()")
						var i, p = $.Progress(1);
						p.on("progress", function(cur, max) {
							log("Progress:", cur, max)
						})
						killAll().then(function() {
							for( i = 0; i < children.length; i++ ) {
								if( children[i] === undefined ) {
									log("reLaunching("+i+")")
									p.include(launchOne(i));
								}
							}
							p.finish(1)
						})
						return p
					},
					killOne = module.exports.killOne = function(i) {
						var p = $.Promise();
						if( children[i] === undefined ) {
							return p.finish();
						}
						log("Killing child["+i+"], pid "+children[i].pid)
						children[i].on('exit', function() {
							log("Child killed: " + children[i].pid)
							p.finish();
						}).kill();
						return p;
					},
					killAll = module.exports.killAll = function() {
						log("killAll()")
						var i, p = $.Progress(1); // start with one step of progress: the set-up
						for( i = 0; i < children.length; i++ ) {
							if( children[i] !== undefined ) {
								log("calling killOne("+i+")")
								p.include(killOne(i));
							}
						}
						try { return p.finish(1); // finish the set-up
						} finally {
							log("killAll - done:", p.finished, p.failed)
						}
					}
			} catch (_err) {
				return log("Caught exception: ", _err);
			}

			try {
				$.publish("http-route", "get", "/list-children", function(req, res) {
					var i, child, html = "<table>";
					for( i = 0; i < children.length; i++ ) {
						child = children[i];
						if( child != null ) {
							html += "<tr><td>" + i + "<td>" + child.pid
						} else {
							html += "<tr><td>" + i + "<td>Dead</td>"
						}
						html += "</tr>"
					}
					res.statusCode = 200;
					res.end(html)
				})
			} catch (_err) {
				log("Caught error:", _err)
			}

			log("Launching children...")
			reLaunchAll().then(function() {
				log("All children launched.")
				httpServer.listen(herd.http.port)
				log("Listening on port", herd.http.port)
			})

		})
	})
}).call(this)
