#!/usr/bin/env node
$ = require 'bling'
Shell = require 'shelljs'
Process = module.exports

log = $.logger "[Process]"

Process.exec = (cmd, verbose) ->
	try return p = $.Promise()
	finally
		try
			if verbose then log "shell >", cmd
			ret = { output: "" }
			child = Shell.exec cmd, { silent: true, async: true }, (exitCode) ->
				try
					if exitCode isnt 0 then p.reject ret.output
					else p.resolve ret.output
				catch err
					log "exec: error handling process exit:", err.stack ? err
			child.stdout.on "data", append_output = (data) -> ret.output += String data
			child.stderr.on "data", append_output
		catch err
			log "exec: error in running process:", err.stack ? err

# for caching the output of 'ps' commands
# mostly to save time in commands like Process.tree
# where possibly hundreds of Process.find calls are generated.
psCache = new $.Cache(2, 300)

ps_cmd = "ps -eo uid,pid,ppid,pcpu,rss,command"
ps_parse = (output) ->
	try
		output = output.split('\n').map((line) -> # split into lines
			line.split(/[ ]+/).slice(1) # split each line on whitespace
		).slice(0,-1) # discard the last line?
		# turn the 2D array of proc data into a list of process objects
		keys = output[0].map $.slugize # parse the first line for the field names
		return output.slice(1).map (row) -> # for each row
			try return ret = Object.create(null) # return an object
			finally for key,i in keys # attach an output value to each key for this row
				if i is keys.length - 1 # the last value (the command) is all concatenated together
					ret[key] = row.slice(i).join(' ')
				else
					val = row[i]
					try # gently attempt to make numbers out of number-like strings
						val = parseInt(val, 10)
						unless isFinite(val) # revert the value on a soft parsing (NaN, Infinity, etc)
							val = row[i]
					catch e
						val = row[i]
					finally
						ret[key] = val
				unless ret[key]?
					log "ps_parse failed to parse line:", key, i, row[i], ret[key]
	catch err
		log "ps_parse error:", err.stack ? err

# given the output of ps_parse, use "lsof" to attach listening ports
lsof_cmd = "lsof -Pni | grep LISTEN"
attach_ports = (procs) ->
	try return attached = $.Promise()
	finally
		try
			index = Object.create null
			for proc in procs
				index[proc.pid] = proc
				proc.ports = []
			Process.exec(lsof_cmd).then (output) ->
				unless output then return attached.resolve procs
				try
					for line in output.split /\n/g
						line = line.split(/\s+/g)
						continue if line.length < 8
						pid = parseInt line[1], 10
						port = parseInt line[8].split(/:/)[1], 10
						unless pid of index
							index[pid] = { pid: pid, ports: [] }
						try
							index[pid].ports.push port
						catch err
							log err, pid, index[pid]
					attached.resolve(procs)
				catch err
					log "attach_ports error while parsing output:", err.stack ? err
		catch err
			log "attach_ports error:", err.stack ? err

Process.clearCache = -> psCache.del ps_cmd; Process

Process.find = (query) ->
	try return p = $.Promise()
	finally
		try
			query = switch $.type query
				when "string" then { cmd: new RegExp query }
				when "number" then { pid: query }
				else query

			if psCache.has ps_cmd
				p.resolve psCache.get(ps_cmd).filter (item) -> $.matches query, item
			else Process.exec(ps_cmd).then ((output) ->
				attach_ports(ps_parse(output)).then ((procs) ->
					try
						p.resolve psCache.set(ps_cmd, procs).filter (item) -> $.matches query, item
					catch err
						log "find error in results:", err.stack ? err
				), p.reject
			), p.reject
		catch err
			log "find error:", err.stack ? err

Process.findOne = (query) ->
	try return p = $.Promise()
	finally Process.find(query).then ((out) ->
		try p.resolve out[0]
		catch err then log "findOne error:", err.stack ? err
	), p.reject

Process.findTree = (query) ->
	try return p = $.Promise()
	finally Process.findOne(query).then (proc) ->
		Process.tree(proc).then p.resolve, p.reject

Process.signals = signals = {
	SIGHUP: 1
	SIGINT: 2
	SIGKILL: 9
	SIGTERM: 15
	HUP: 1
	INT: 2
	KILL: 9
	TERM: 15
}

Process.getSignalNumber = (signal) ->
	signals[signal] ? (if $.is 'number', signal then signal else 15)

Process.kill = (pid, signal) ->
	try Process.exec "kill -#{Process.getSignalNumber signal} #{pid}"
	catch err then log "kill error:", err.stack ? err

Process.tree = (proc) ->
	try return q = $.Promise()
	finally
		p = $.Progress 1
		if proc then Process.find({ ppid: proc.pid }).then ((children) ->
			try
				proc.children = children
				for child in children
					p.include Process.tree child
				p.resolve(1, proc)
			catch err
				log "tree error:", err.stack ? err
		), q.reject
		p.then (-> q.resolve proc), q.reject

Process.walk = (node, visit, depth=0) ->
	try return p = $.Progress(1)
	finally
		try p.include visit node, depth
		catch err
			log "walk error (in visit):", err.stack ? err
			p.reject err
		for child in node.children
			p.include Process.walk child, visit, depth + 1
		p.finish(1)

Process.killTree = (proc, signal) ->
	try return p = $.Promise()
	finally
		try
			signal = Process.getSignalNumber(signal)
			proc = switch $.type proc
				when 'string','number' then { pid: proc }
				else proc
			tokill = []
			fail = (msg, err) ->
				log msg, err?.stack ? err
				p.reject err
			Process.tree(proc).then ((tree) ->
				try
					Process.walk tree, (node) ->
						if node.pid then tokill.push node.pid
						else fail "killTree invalid node (no pid):", node
					if tokill.length
						Process.exec("kill -#{signal} #{tokill.join ' '} &> /dev/null")
							.then p.resolve, (err) ->
								fail "killTree error while killing", err
				catch err then fail "killTree error while walking:", err
			), p.reject
		catch err then fail "killTree error:", err

Process.summarize = (proc) -> # currently kind of worthless, needs to use depth
	proc.rss = proc.cpu = 0
	try return p = $.Promise()
	finally Process.tree(proc).then (tree) ->
		Process.walk tree, (node, depth) ->
			proc.rss += node.rss # sum values upwards
			proc.cpu += node.cpu
		p.resolve tree

Process.printTree = (proc, indent, spacer) ->
	try
		spacer or= " \\_"
		indent or= "* "
		ret = indent + proc.pid + " " + proc.command
		if proc.ports?.length then ret += " [:" + proc.ports.join(", :") + "]"
		ret += " {mem: #{$.commaize proc.rss}kb cpu: #{proc.cpu}%}\n"
		indent = spacer + indent
		for child in proc.children
			ret += Process.printTree child, indent, "   "
		indent.replace /^   /,''
		return ret
	catch err
		log "printTree error:", err.stack ? err

if require.main is module
	port = parseInt(process.argv[2], 10) || 8000
	log "Tree for owner of:", port
	Process.find({ ports: port }).then (procs) ->
		for proc in procs
			Process.tree(proc).then (tree) ->
				console.log Process.printTree tree
