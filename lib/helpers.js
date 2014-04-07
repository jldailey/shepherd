var $ = require('bling'),
	Shell = require('shelljs'),
	Fs = require('fs')

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

// Make a helper for executing shell commands and collecting their output
// This is meant for one-off commands that end quickly, not long-running server process
$.Promise.exec = function(cmd) {
	var p = $.Promise(),
		output = "",
		child = Shell.exec(cmd, { silent: true, async: true }, function(exitCode) {
			if( exitCode != 0 ) p.fail(output);
			else p.finish(output)
		}),
		append_output = function(data) { output += data.toString() }
	git.stdout.on("data", append_output);
	git.stderr.on("data", append_output);
	return p;
}
