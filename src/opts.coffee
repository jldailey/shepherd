pkg = JSON.parse require("fs").readFileSync __dirname + "/../package.json"
require("bling").extend module.exports, require("commander")
	.version(pkg.version)
	.option '-f [file]', "The herd file to load", null
	.option '-o [file]', "Where to send log output.\nNote: output to stdout is synchronous (blocking).", "-"
	.option '--defaults', "Output the default configuration."
	.option '--daemon', "Run in the background."
	.option '-p [file]', "The .pid file to use (if a daemon).", "shepherd.pid"
	.option '--verbose', "Verbose mode."
	.parse process.argv


