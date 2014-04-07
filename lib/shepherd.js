(function() {

	var $ = require("bling"),
		Shell = require("shelljs"),
		Fs = require("fs"),
		Opts = require("commander"),
		Http = require('http'),
		Os = require('os');
	
	// Make a helper for reading JSON data (through a Promise)
	$.Promise.jsonFile = function(file, p) {
		// Use a default (empty) promise
		if (p == null) p = $.Promise();
		// Set a default error handler
		p.wait(function(err, obj) {
			if (err) return $.log("jsonFile(" + file + ") failed:", err);
		});
		// Read the file
		Fs.readFile(file, function(err, data) {
			if (err) return p.fail(err);
			try {
				return p.finish(JSON.parse(data));
			} catch (_err) {
				return p.fail(_err);
			}
		});
		return p;
	};

	log = $.logger("[shepherd]");

	log("Starting as PID:", process.pid);

	// Read our own package.json
	$.Promise.jsonFile(__dirname + "/../package.json").then(function(pkg) {

		log("Parsed package.json...")

		// Parse command-line options
		Opts.version(pkg.version)
			.option('-f [file]', "The .herd file to load", ".herd")
			.parse(process.argv);

		// make sure a herd object has all the right stuff
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
				httpPort: 9000
			}, herd.git)

			herd.env = $.extend({
			}, herd.env)

			log("Sanitized herd:", herd);

			return herd;
		}

		function makeEnvString(env) {
			var ret = "";
			for( key in env ) {
				ret += 'key="'+env[key]+'" '
			}
			return ret
		}

		$.Promise.jsonFile(Opts.F).wait(function(err, herd) {
			if( err ) return log("Error: ", err)
			log("Parsed .herd file:", Opts.F);
			var i,
				herd = sanitizeHerd(herd),
				maxChildren = 'count' in herd ? herd.count : os.cpus().length - 1,
				children = new Array(maxChildren), // the list of child processes,
				startAttempts = 0, // use these to enforce herd.restart.maxAttempts
				restartTimeout = null,
				isDefined = function(x) { return x !== undefined },
				launchOne = module.exports.launchOne = function(i) { // launches a single child
					if( i < 0 || i >= children.length ) return $.Promise().fail("Invalid child index.");
					var started = $.Promise(),
						port = herd.port + i,
						child_count = $(children).filter(isDefined),
						env_string = makeEnvString($.extend(herd.env, { PORT: port })),
						child = Shell.exec(env_string + herd.command, { silent: true, async: true }, function(exitCode) {
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
						})
					child_log = $.logger("child[" + i + "](" + child.pid + ")");
					child_err = $.logger("child[" + i + "](" + child.pid + ")(stderr)");
					child.stdout.on("data", function(data) {
						started.finish()
						child_log(data)
					})
					child.stderr.on("data", function(data) {
						started.fail()
						child_err(data)
					})
					return started;
				},
				reLaunchAll = module.exports.reLaunchAll = function() {
					var i, p = $.Progress(1);
					killAll().then(function() {
						for( i = 0; i < children.length; i++ ) {
							if( children[i] === undefined ) {
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
					var i, p = $.Progress(1); // start with one step of progress: the set-up
					for( i = 0; i < children.length; i++ ) {
						if( children[i] !== undefined ) {
							p.include(killOne(i));
						}
					}
					return p.finish();
				},
				httpServer = module.exports.httpServer = Http.createServer(function(req, res) { // to listen for webhooks
					if( req.method = "POST" ) {
						httpOnPost(req, res);
					}
					res.statusCode = 200;
					return res.end("Listening on " + herd.httpPort + " for webhook POSTs.");
				}),
				httpOnPost = function (req, res) {
					var obj,
						end = function (code, msg) {
							res.statusCode = code;
							res.end(msg);
						},
						fail = function(msg) {
							end(500, msg);
						};
					try { obj = JSON.parse(req.body) }
					catch (err) {
						return fail(String(err));
					}
					return end(200, "Hello")
				},
				gitPull = function() {
					var output = "",
						p = $.Promise(),
						git = Shell.exec("git pull " + herd.git.remote + " " + herd.git.branch, { silent: true, async: true }, function(exitCode) {
							if( exitCode != 0 ) p.fail(output);
							else p.finish(output)
						})
					git.stdout.on("data", function(data) {
						output += data.toString()
					})
					git.stderr.on("data", function(data) {
						output += data.toString()
					})
					return p;
				};
			log("Parsed herd:", herd);

			reLaunchAll().then(function() {
				log("All children launched.")
			})

			log("Starting HTTP server for webhooks...");
			httpServer.listen(herd.git.httpPort, function(err) {
				if (err) {
					log("Failed to listen on PORT:", herd.git.httpPort, err);
					process.exit(1);
				} else {
					log("HTTP Server ready for webhooks");
				}
			})
		})
	})
}).call(this)
