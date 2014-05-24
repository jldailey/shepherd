
var $ = require("bling"),
	Shell = require("shelljs"),
	Fs = require("fs"),
	Opts = require("commander"),
	Util = require("util"),
	Http = require('./http'),
	Helpers = require('./helpers'),
	Herd = require('./herd'),
	log = $.logger("[shepherd]")

// Read our own package.json
$.Promise.jsonFile(__dirname + "/../package.json").wait(function(err, pkg) {

	if( err ) {
		log(err.stack);
		process.exit(1)
	}

	// Parse command-line options
	Opts.version(pkg.version)
		.option('-f [file]', "The herd file to load", ".herd")
		.option('-o [file]', "Where to send log output", "-")
		.option('--defaults', "Output a complete herd file with all defaults")
		.option('--daemon', "Run in the background.")
		.option('-p [file]', "The .pid file to use.", "shepherd.pid")
		.parse(process.argv);

	if( Opts.defaults ) {
		var defaults = Herd.defaults()
		console.log(Util.inspect(defaults).replace(/(\s)(\w+):/g,'$1"$2":').replace(/'/g,'"'))
		process.exit(0)
	}

	if( Opts.daemon ) {
		require('daemon')()
		Fs.writeFileSync(Opts.P, String(process.pid))
	}

	if( Opts.O != "-" ) {
		try {
			var outStream = Fs.createWriteStream(Opts.O, { flags: 'a', mode: 0666, encoding: 'utf8' })
		} catch( err ) {
			console.error("Failed to establish output stream to "+Opts.O)
			console.error(err.stack)
			process.exit(1);
		}
		$.log.out = function() {
			try {
				msg = Array.prototype.slice.call(arguments, 0).join(' ')
				outStream.write(msg, 'utf8')
			} catch( err ) {
				console.error("Failed to write to "+Opts.O)
				console.error(err.stack)
				process.exit(1);
			}
		}
	}



	// Read the configuration
	$.Promise.jsonFile(Opts.F).then(function(herd) {
		// create the new herd
		herd = new Herd(herd)
		log("Starting new herd, shepherd PID: " + process.pid)
		// start all the processes
		herd.rollingRestart().wait(function(err) {
			if( err != null ) return log(err)
			// start the admin server
			Http.listen(herd.http.port)

			// write the nginx config (if enabled)
			herd.writeConfig()
		})
	})

})
