var $ = require('bling'),
	Shell = require('shelljs'),
	Fs = require('fs'),
	Os = require('os'),
	Opts = require('./opts'),
	Helpers = module.exports

log = $.logger("[helper]")

// Make a helper for reading JSON data (through a Promise)
Helpers.jsonFile = function(file, p) {
	// Use a default (empty) promise
	if (p == null) p = $.Promise();
	// Set a default error handler
	p.wait(function(err, obj) {
		if (err) return log("jsonFile(" + file + ") failed:", err);
	});
	// Read the file
	Fs.readFile(file, function(err, data) {
		if (err) return p.reject(err);
		try {
			return p.resolve(JSON.parse(data));
		} catch (_err) {
			return p.reject(_err);
		}
	});
	return p;
};

Helpers.delay = function(ms) {
	var p = $.Promise();
	$.delay(ms, function() {
		p.resolve()
	})
	return p;
}

// wait until a certain pid (or it's child) is listening on a port
Helpers.portIsOwned = function(pid, port, timeout) {
	var p = $.Promise(),
		started = $.now,
		target_pids = [],
		poll_port = function() {
			if( $.now - started > timeout )
				return p.reject("Waiting failed after a timeout of: " + timeout + "ms")
			Process.findOne({ ports: port }).then(function(owner) {
				// if there is no owner, or the owner is not one of our targets
				if( (! owner) || (! $.matches(owner.pid, target_pids) )  ) {
					// poll again later
					setTimeout(poll_port, 300)
				} else {
					p.resolve(owner)
				}
			}, p.reject)
		}
	
	// find all children of our target pid
	Process.tree({ pid: pid }).then(function(tree) {
		Process.walk(tree, function(node) {
			target_pids.push(node.pid)
		})
		started = $.now // set the real start time
		// now start polling the port until it is owned
		poll_port()
	})

	return p;
}
