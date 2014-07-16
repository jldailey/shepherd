var $ = require('bling'),
	Shell = require('shelljs'),
	Fs = require('fs'),
	Os = require('os'),
	Opts = require('./opts')

log = $.logger("[helper]")

// Make a helper for reading JSON data (through a Promise)
$.Promise.jsonFile = function(file, p) {
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

// Make a helper for executing shell commands and collecting their output
// This is meant for one-off commands that end quickly, not long-running server process
$.Promise.exec = function(cmd) {
	try {
		var p = $.Promise(),
			ret = { output: "" }
			child = Shell.exec(cmd, { silent: true, async: true }, function(exitCode) {
				if( exitCode != 0 ) p.reject(ret.output);
				else {
					p.resolve(ret.output)
				}
			}),
			append_output = function(data) { ret.output += data.toString() }
		child.stdout.on("data", append_output);
		child.stderr.on("data", append_output);
	} catch (_err) {
		p.reject(_err)
	}
	return p;
}

$.Promise.delay = function(ms) {
	var p = $.Promise();
	$.delay(ms, function() {
		p.resolve()
	})
	return p;
}

// wait until a certain pid is listening on a port
$.Promise.portIsOwned = function(pid, port, timeout) {
	var p = $.Promise(),
		started = $.now
	$.Promise.allChildrenOf(pid).wait(function(err, children) {
		var poll_port = function() {
			if( $.now - started > timeout ) {
				return p.reject("Waiting failed after a timeout of: " + timeout + "ms")
			}
			$.Promise.portOwner(port).wait(function (err, owner) {
				if( err != null ) p.reject(err)
				else if( children.indexOf(String(owner)) > -1 ) p.resolve(owner)
				else setTimeout(poll_port, 300)
			})
		}
		poll_port()
	})
	return p;
}

// returns the pid of the process listening on the port
$.Promise.portOwner = function(port) {
	var p = $.Promise(),
		cmd = "lsof -i :"+port+" | grep LISTEN | awk '{print \$2}'"
	$.Promise.exec(cmd).wait(function(err, pid) {
		if(err != null) return p.reject(err)
		else try { return p.resolve(parseInt(pid, 10))	}
		catch (parse_err) { return p.reject(parse_err) }
	})
	return p
}

$.Promise.childOf = function(pid) {
	var p = $.Promise()
	$.Promise.exec("ps axj | grep '\\<"+pid+"\\>' | grep -v grep | awk '{print \$3}' ").wait(function(err, output) {
		if( err != null ) return p.reject(err)
		try { p.resolve(parseInt(output, 10)) }
		catch (err) { p.reject(err) }
	})
	return p
}

$.Promise.allChildrenOf = function(pid) {
	var cmd, pid = String(pid), p = $.Promise()
	switch( Os.platform() ) {
		case "darwin":
			cmd = "ps -axlf | awk '{print \$2 \" \" \$3}'"
			break
		case "linux":
			cmd = "ps -axlf | awk '{print \$3 \" \" \$4}'"
			break
		default:
			p.reject('unsupported platform: '+Os.platform())
	}
	$.Promise.exec(cmd).wait(function(err, output) {
		var pids = $(String(output).split("\n")).map(function(line){ return line.split(" ") }),
			children = [pid],
			pid_stack = [pid],
			current_pid = null

		// since different platforms output the data in different orders
		// we have to do it this way where we re-query the whole dataset
		while( pid_stack.length > 0 ) {
			current_pid = pid_stack.shift()
			pids.each(function(item) {
				if( item[1] == current_pid ) {
					pid_stack.unshift(item[0])
					children.push(item[0])
				}
			})
		}

		p.resolve(children)
	})
	return p
}

