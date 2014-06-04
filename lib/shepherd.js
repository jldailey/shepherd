
var $ = require("bling"),
	Shell = require("shelljs"),
	Fs = require("fs"),
	Opts = require("commander"),
	Util = require("util"),
	Helpers = require('./helpers'),
	log = $.logger("[shepherd]"),
	Herd, Opts;

// Parse command-line options
Opts = require('./opts')
Herd = require('./herd')

function pretty_json(obj) {
	console.log(Util.inspect(obj).replace(/(\s)(\w+):/g,'$1"$2":').replace(/'/g,'"'))
}

if( Opts.defaults && Opts.F == null ) {
	pretty_json(Herd.defaults())
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
	var _slice = Array.prototype.slice
	$.log.out = function() {
		try {
			msg = _slice.call(arguments, 0).join(' ') + "\n"
			outStream.write(msg, 'utf8')
		} catch( err ) {
			console.error("Failed to write to "+Opts.O)
			console.error(err.stack)
			process.exit(1);
		}
	}
}

// Read the configuration
$.Promise.jsonFile(Opts.F).wait(function(err, herdOpts) {
	if( err ) {
		log("Failed to open herd file:", Opts.F, err.stack)
		return process.exit(1)
	}
	log("Starting new herd, shepherd PID: " + process.pid)
	// create the new herd
	herd = new Herd(herdOpts)
	// start the admin server
	herd.listen()
	// write the nginx config (if enabled)
	herd.writeConfig()
	// start all the processes
	herd.rollingRestart()
})

