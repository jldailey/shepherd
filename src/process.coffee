#!/usr/bin/env node
$ = require 'bling'
Shell = require 'shelljs'
Process = module.exports

log = $.logger "[Process]"

Process.exec = (cmd, verbose) ->
	try return p = $.Promise()
	finally
		if verbose then log "shell >", cmd
		ret = { output: "" }
		child = Shell.exec cmd, { silent: true, async: true }, (exitCode) ->
			if exitCode isnt 0 then p.reject ret.output
			else p.resolve ret.output
		child.stdout.on "data", append_output = (data) -> ret.output += String data
		child.stderr.on "data", append_output

# for caching the output of 'ps' commands
# mostly to save time in commands like Process.tree
# where possibly hundreds of Process.find calls are generated.
psCache = new $.Cache(2, 100)

ps_cmd = "ps -eo uid,pid,ppid,pcpu,rss,command"
ps_parse = (output) ->
	output = output.split('\n').map((line) -> # split into lines
		line.split(/[ ]+/).slice(1) # split each line on whitespace
	).slice(0,-1)
	 # .slice(0,-1) # discard the last line?
	# turn the 2D array of proc data into a list of process objects
	keys = output[0].map $.slugize # parse the first line for the field names
	return output.slice(1).map (row) -> # for each row
		try return ret = Object.create(null) # return an object
		finally for key,i in keys # attach an output value to each key for this row
			if i is keys.length - 1
				ret[key] = row.slice(i).join(' ') # the last value (the command) is all concatenated together
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
				console.log key, i, row[i], ret[key]

lsof_cmd = "lsof -Pni | grep LISTEN"
attach_ports = (procs) -> # given the output of ps_parse, use "lsof" to attach listening ports
	try return attached = $.Promise()
	finally
		index = Object.create null
		for proc in procs
			index[proc.pid] = proc
			proc.ports = []
		Process.exec(lsof_cmd).then (output) ->
			for line in output.split /\n/g
				line = line.split(/\s+/g)
				continue if line.length < 8
				pid = parseInt line[1], 10
				port = parseInt line[8].split(/:/)[1], 10
				try
					index[pid].ports.push port
				catch err
					log err, pid, index[pid]
			attached.resolve(procs)

Process.clearCache = -> psCache.del ps_cmd; Process

Process.find = (query) ->
	try return p = $.Promise()
	finally
		query = switch $.type query
			when "string" then { cmd: new RegExp query }
			when "number" then { pid: query }
			else query

		if psCache.has ps_cmd
			p.resolve psCache.get(ps_cmd).filter (item) -> $.matches query, item
		else Process.exec(ps_cmd).then ((output) ->
			attach_ports(ps_parse(output)).then ((procs) ->
				p.resolve psCache.set(ps_cmd, procs).filter (item) -> $.matches query, item
			), p.reject
		), p.reject

Process.findOne = (query) ->
	try return p = $.Promise()
	finally Process.find(query).then ((out) ->
		p.resolve out[0]
	), p.reject

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

Process.kill = (pid, signal) -> Process.exec "kill -#{Process.getSignalNumber signal} #{pid}", true

Process.tree = (proc) ->
	try return q = $.Promise()
	finally
		p = $.Progress 1
		if proc then Process.find({ ppid: proc.pid }).then ((children) ->
			proc.children = children
			for child in children
				p.include Process.tree child
			p.resolve(1, proc)
		), q.reject
		p.then (-> q.resolve proc), q.reject

Process.walk = (node, visit) ->
	try return p = $.Progress(1)
	finally
		try p.include visit node catch e then p.reject e
		for child in node.children
			p.include Process.walk child, visit
		p.finish(1)

Process.killTree = (proc, signal) ->
	try return p = $.Promise()
	finally
		signal = Process.getSignalNumber(signal)
		proc = switch $.type(proc)
			when 'string','number' then { pid: proc }
			else proc
		Process.tree(proc).then ((tree) ->
			Process.walk tree, (node) ->
				if node.pid
					log("Death is visiting:", node.pid, "with signal", signal)
					Process.kill node.pid, signal
			p.resolve()
		), p.reject

Process.summarize = (proc) ->
	proc.rss = proc.cpu = 0
	try return p = $.Promise()
	finally Process.tree(proc).then (tree) ->
		Process.walk tree, (node) ->
			proc.rss += node.rss # sum values upwards
			proc.cpu += node.cpu
			node.rss = proc.rss # and push the result down
			node.cpu = proc.cpu
		p.resolve tree

Process.printTree = (proc, indent, spacer) ->
	spacer or= "\\_"
	indent or= "* "
	ret = indent + proc.pid + " " + proc.command
	if proc.ports?.length then ret += " [:" + proc.ports.join(", :") + "]"
	ret += " {mem: #{$.commaize proc.rss}kb cpu: #{proc.cpu}%}\n"
	indent = spacer + indent
	for child in proc.children
		ret += Process.printTree child, indent, "   "
	indent.replace /^   /,''
	return ret

if require.main is module
	port = parseInt(process.argv[2], 10) || 8000
	log "Tree for owner of:", port
	Process.find({ ports: port }).then (procs) ->
		for proc in procs
			Process.tree(proc).then (tree) ->
				console.log Process.printTree tree
