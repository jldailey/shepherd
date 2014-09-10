#!/usr/bin/env node
var $ = require('bling'),
	Shell = require('shelljs'),
	log = $.logger("[Process]"),
	Process = module.exports;

Process.exec = function(cmd) {
	try {
		log("exec:", cmd)
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

// for caching the output of 'ps' commands
// mostly to save time in commands like Process.tree
// where possibly hundreds of Process.find calls are generated.
var psCache = new $.Cache(3, 200)

Process.find = function(query) {
	switch ($.type(query)) {
		case "string":
			query = { cmd: new RegExp(query) }
			break;
		case "number":
			query = { pid: query }
			break;
	}

	var p = $.Promise(),
		fail = function(err) { p.reject(err) },
		ps_cmd = "ps -eo uid,pid,ppid,pcpu,vsz,command",
		lsof_cmd = "lsof -Pi | grep LISTEN",
		parse_ps_output = function(output) { // slice up the output string into a 2D array based on newline n and white-space
			output = $(output.split('\n')).map(function(line) { return line.split(/ +/).slice(1) }).slice(0,-1)
			// turn the 2D array of proc data into a list of process objects
			var keys = output[0].map($.slugize);
			return output.slice(1).map(function(row) {
				var i, key, val, ret = Object.create(null);
				for( i = 0; i < keys.length; i++ ) {
					key = keys[i];
					// attach an output value to the right key
					if( i === keys.length - 1 ) {
						// the last value (the command) is all concatenated together
						ret[key] = row.slice(i).join(' ')
					} else {
						val = row[i];
						// gently attempt to make numbers out of number-like strings
						try {
							val = parseInt(val, 10)
							if( ! isFinite(val) ) // revert the value on a soft parsing (NaN, Infinity, etc)
								val = row[i]
						} catch (e) {
							val = row[i];
						} finally {
							ret[key] = val;
						}
					}
				}
				return ret;
			})
		},
		attach_ports = function(procs) {
			var attached = $.Promise()
			procs.forEach(function(proc) {
				proc.ports = []
			})
			Process.exec(lsof_cmd).then(function(output) {
				output.split(/\n/g).forEach(function(line) {
					var i, pid, port, proc;
					line = line.split(/\s+/g)
					if( line.length < 8 ) {
						return;
					}
					pid = parseInt(line[1], 10)
					port = parseInt(line[8].split(/:/)[1], 10)
					for( i = 0; i < procs.length; i++ ) {
						proc = procs[i];
						if( proc.pid == pid ) {
							proc.ports.push(port);
						}
					}
				})
				attached.resolve(procs)
			})
			return attached
		}
	
	if( psCache.has(ps_cmd) ) {
		return p.resolve(psCache.get(ps_cmd).filter(function(item) {
				return $.matches(query, item)
		}));
	}

	Process.exec(ps_cmd).then(function(output) {
		attach_ports(parse_ps_output(output)).then(function(procs) {
			$(procs).zap("kill", function(proc) { return function(signal) { return Process.kill(proc, signal); } })
			p.resolve(psCache.set(ps_cmd, procs).filter(function(item) {
				return $.matches(query, item)
			}))
		})
	}, fail)

	return p
}

Process.findOne = function(query) {
	var p = $.Promise();
	Process.find(query).then(function(out) {
		p.resolve(out[0]);
	}, p.reject)
	return p
}

var signals = Process.signals = {
	SIGHUP: 1,
	SIGINT: 2,
	SIGKILL: 9,
	SIGTERM: 15
}
function getSignalNumber(signal) {
	if( signal in signals ) {
		return signals[signal];
	} else if( $.is("number", signal) ) {
		return signal;
	} else {
		return 15; // SIGTERM by default
	}
}

Process.kill = function(pid, signal) {
	signal = getSignalNumber(signal)
	return Process.exec("kill -" + signal + " " + pid)
}

Process.tree = function(proc) {
	var p = $.Progress(1), r = $.Promise();
	if( proc ) {
		Process.find({ ppid: proc.pid }).then(function(children) {
			proc.children = children
			$(children).each(function(child) {
				p.include(Process.tree(child))
			})
			p.resolve(1, proc)
		})
	}
	p.then(function() { r.resolve(proc) }, r.reject)
	return r
}

Process.walk = function(node, visit) {
	visit(node)
	$(node.children).each(function(child){ Process.walk(child, visit) })
}

Process.killTree = function(proc, signal) {
	log("Killing process tree:", proc)
	signal = getSignalNumber(signal)
	Process.tree(proc).then(function(tree) {
		Process.walk(tree, function(node) {
			log("Death is visiting:", node.pid, "with signal", signal)
			Process.kill(node.pid, signal)
		})
	})
}

function printTree(node, indent, spacer) {
	spacer = spacer || "\\_"
	indent = indent || "* "
	var ret = indent + node.pid + " " + node.command
	if( node.ports.length > 0 ) ret += " [:" + node.ports.join(", :") + "]";
	ret += "\n";
	indent = spacer + indent
	$(node.children).each(function(child) {
		ret += printTree(child, indent, "   ")
	})
	indent.replace(/^   /,'')
	return ret;
}

if( require.main == module ) {
	var port = parseInt(process.argv[2], 10) || 8000
	log("Tree for owner of:", port)
	Process.findOne({ ports: port } ).then(function(proc) {
		Process.tree(proc).then(function(tree) { console.log(printTree(tree)) })
	})
}
