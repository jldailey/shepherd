pkg = JSON.parse require("fs").readFileSync __dirname + "/../package.json"
require("bling").extend module.exports, require("commander")
	.version(pkg.version)
	.option '-f [file]', "The herd configuration file to load", null
	.option '-o [file]', "Where to send log output.\n\tNote: output to a tty is synchronous (blocking).", "-"
	.option '--example', "Output a complete sample configuration."
	.option '-d --daemon', "Run in the background."
	.option '-p [file]', "Write process.pid to this file.", "shepherd.pid"
	.option '-v --verbose', "Verbose mode."
	.parse process.argv


