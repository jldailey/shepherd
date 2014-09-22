$ = require('bling')
Shell = require('shelljs')
Fs = require('fs')
Os = require('os')
log = $.logger("[helper]")
Helpers = module.exports

# Make a helper for reading JSON data (through a Promise)
Helpers.jsonFile = (file, p) ->
	# Use a default (empty) promise
	p ?= $.Promise()
	# Set a default error handler
	p.wait (err, obj) ->
		if err then return log("jsonFile(" + file + ") failed:", err)
	# Read the file
	Fs.readFile file, (err, data) ->
		if err then return p.reject err
		try p.resolve JSON.parse String data
		catch _err then p.reject _err
		null
	return p

Helpers.delay = (ms) ->
	p = $.Promise()
	$.delay ms, ->
		p.resolve()
	p

# wait until a certain pid (or it's child) is listening on a port
Helpers.portIsOwned = (pid, port, timeout) ->
	p = $.Promise()
	started = $.now
	target_pids = []
	poll_port = ->
		if( $.now - started > timeout )
			return p.reject("Waiting failed after a timeout of: " + timeout + "ms")
		Process.findOne({ ports: port }).then ((owner) ->
			# if there is no owner, or the owner is not one of our targets
			if (not owner) or (not $.matches owner.pid, target_pids)
				# poll again later
				setTimeout(poll_port, 300)
				log("Waiting for port (" + port + ") to be owned by one of:", target_pids)
			else p.resolve(owner)
		), p.reject

	# find all children of our target pid
	Process.tree({ pid: pid }).then (tree) ->
		Process.walk tree, (node) ->
			target_pids.push(node.pid)
		started = $.now # set the real start time
		poll_port() # now start polling the port until it is owned

	return p

if require.main is module
	return if process.argv.length < 4
	port = parseInt(process.argv[2], 10)
	pid = parseInt(process.argv[3], 10)
	Process = require("./process")
	Helpers.portIsOwned(pid, port, 3000).then($.log, console.error.bind(console))
