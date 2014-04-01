(function() {

  var $ = require("bling"),
		Shell = require("shelljs"),
		Fs = require("fs"),
		Opts = require("commander"),
		Http = require('http')

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
  $.Promise.jsonFile(__dirname + "../package.json").then(function(pkg) {

		// Parse command-line options
    Opts.version(pkg.version)
			.option('-f [file]', "The .herd file to load", ".herd")
			.option('-x [n]', "Exit code that causes an auto-restart", parseInt, 3)
			.option('-m [n]', "Maximum restarts in fast succession.", parseInt, 3)
			.option('-t [s]', "Number of seconds to wait before clearing restart timeout.", parseInt, 10)
			.parse(process.argv);

    $.Promise.jsonFile(Opts.f).then(function(herd) {
      var i,
				maxChildren = parseInt(herd.number, 10), // the size of the flock we would like to keep alive
				children = new Array(maxChildren), // the list of child processes,
				launchOne = function(i) { // launches a single child
					var started = $.Promise(),
						port = herd.port + i,
						cmd_string = "PORT=" + port + " " + Opts.command,
						start_attempts = 0,
						restartTimeout = null,
						child = Shell.exec(cmd_string, {
							silent: true,
							async: true
						}, function(exit_code) {
							log("Child PID: " + child.pid + " Exited with exit_code: ", exit_code);
							// find the dead child's index
							var child_index = $(children).select('pid').indexOf(pid),
								// use these to enforce Opts.maxRestart
								start_attempts = 0,
								restartTimeout = null;

							if( child_index > -1 ) {
								children[child_index] = undefined;
							}
							// if it died with a restartable exit code, attempt to restart it
							if (exit_code === Opts.restartCode && (++start_attempts) < Opts.maxRestart) {
								clearTimeout(restartTimeout);
								restartTimeout = setTimeout( function() {
									// after a while, forget about previous start attempts
									start_attempts = 0;
								}, Opts.restartTimeout)
								// restart the child
								launchOne(i);
							} else if (children.length === 0) {
								log("All children exited gracefully, shutting down (no flock to tend).");
								process.exit(0);
							} else {
								log("Still " + children.length + " children running");
							}
							clearTimeout(restartTimeout);
							return restartTimeout = setTimeout((function() {
								return start_attempts = 0;
							}), Opts.restartTimeout);
						}));
					child_log = $.logger("[child-" + child.pid + "]");
					child.stdout.on("data", function(data) {
						started.finish()
						child_log(data)
					})
					child.stderr.on("data", function(data) {
						started.fail()
						child_log("(stderr)", data)
					})
					return started;
				},
				reLaunchAll = function() {
					var i, toRestart = 0, p = $.Progress();
					for( i = 0; i < children.length; i++ ) {
						if( children[i] === undefined ) {
							p.include(launchOne(i));
						}
					}
					return p
				},
				killOne = function(i) {
					var p = $.Promise();
					children[i].on('exit', function() {
						p.finish();
					}).kill();
					return p;
				},
				killAll = function() {
					var i, p = $.Progress();
					for( i = 0; i < children.length; i++ ) {
						if( children[i] !== undefined ) {
							p.include(killOne(i));
						}
					}
					return p;
				},
				httpServer = Http.createServer(function(req, res) { // to listen for webhooks
					var obj,
						fail = function(msg) {
							res.statusCode = 500;
							res.end(msg);
						};
					if( req.method = "POST" ) {
						try { obj = JSON.parse(req.body) }
						catch (err) {
							return fail(String(err));
						}
					}
					res.statusCode = 200;
					return res.end("Thanks for coming.");
				}),
			reLaunchAll().then ->
				log "All children launched."

      log("Starting HTTP server...");
      httpServer.listen(herd.httpPort, function(err) {
        if (err) {
          log("Listen error:", err);
          process.exit(1);
        } else {
          log("HTTP Server ready for webhooks");
        }
      })
    })
  })
}).call(this)
