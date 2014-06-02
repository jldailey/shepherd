
(function(opts, fs, $) {

	var pkg = JSON.parse(fs.readFileSync(__dirname + "/../package.json"))
	opts.version(pkg.version)
		.option('-f [file]', "The herd file to load", null)
		.option('-o [file]', "Where to send log output.\nNote: output to stdout is synchronous (blocking).", "-")
		.option('--defaults', "Output a complete herd file with all defaults")
		.option('--daemon', "Run in the background.")
		.option('--verbose', "Verbose mode.")
		.option('-p [file]', "The .pid file to use.", "shepherd.pid")
		.parse(process.argv);

	$.extend(module.exports, opts)

})(require("commander"), require("fs"), require("bling"))

