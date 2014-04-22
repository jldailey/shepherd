var $ = require('bling'),
	Shell = require('shelljs'),
	Fs = require('fs')

log = $.logger("[helper]")

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
	try {
		var p = $.Promise(),
			ret = { output: "" }
			child = Shell.exec(cmd, { silent: true, async: true }, function(exitCode) {
				if( exitCode != 0 ) p.fail(ret.output);
				else {
					p.finish(ret.output)
				}
			}),
			append_output = function(data) { ret.output += data.toString() }
		child.stdout.on("data", append_output);
		child.stderr.on("data", append_output);
	} catch (_err) {
		p.fail(_err)
	}
	return p;
}

$.Promise.delay = function(ms) {
	var p = $.Promise();
	$.delay(ms, function() {
		p.finish()
	})
	return p;
}

// wait until a certain pid is listening on a port
$.Promise.portIsOwned = function(pid, port, timeout) {
	var p = $.Promise(),
		started = $.now,
		wait_once = function() {
			if( $.now - started > timeout ) {
				return fail("Waiting failed after a timeout of: " + timeout + "ms")
			}
			$.Promise.portOwner(port).wait(function (err, owner) {
				if( err != null ) return p.fail(err)
				if( pid == owner ) return p.finish(owner)
				$.Promise.childOf(owner).wait(function (err, child) {
					if( err != null ) return p.fail(err)
					if( pid == child ) return p.finish(owner)
					else setTimeout(wait_once, 300)
				})
			})
		}
	wait_once()
	return p;
}

// returns the pid of the process listening on the port
$.Promise.portOwner = function(port) {
	var p = $.Promise(),
		cmd = "lsof -i :"+port+" | grep LISTEN | awk '{print \$2}'"
	$.Promise.exec(cmd).wait(function(err, pid) {
		if(err != null) return p.fail(err)
		else try { return p.finish(parseInt(pid, 10))	}
		catch (parse_err) { return p.fail(parse_err) }
	})
	return p
}

$.Promise.childOf = function(pid) {
	var p = $.Promise()
	$.Promise.exec("ps axj | grep '\\<"+pid+"\\>' | grep -v grep | awk '{print \$3}' ").wait(function(err, output) {
		if( err != null ) return p.fail(err)
		try { p.finish(parseInt(output, 10)) }
		catch (err) { p.fail(err) }
	})
	return p
}
