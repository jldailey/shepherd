$       = require 'bling'
Fs      = require 'fs'
Os      = require 'os'
Shell   = require 'shelljs'
HJson   = require 'hjson'
Process = require './process'
Helpers = module.exports
log     = $.logger "[helper]"

# Make a helper for reading JSON data (through a Promise)
Helpers.readJson = (file, p) ->
	p ?= $.Promise() # Use a default (empty) promise
	p.wait (err, obj) -> # Set a default error handler
		if err then return log("readJson(" + file + ") failed:", err)
	Fs.readFile file, (err, data) -> # Read the file
		if err then return p.reject err
		try p.resolve HJson.parse String data
		catch _err then p.reject _err
		null
	return p

Helpers.delay = (ms) ->
	p = $.Promise()
	$.delay ms, p.resolve
	p

# wait until a certain pid (or it's child) is listening on a port
Helpers.portIsOwned = (pid, port, timeout, verbose) ->
	try return p = $.Promise()
	finally
		started = $.now
		do poll_port = ->
			if $.now - started > timeout
				return p.reject "Waiting failed after a timeout of: " + timeout + "ms"
			target_pids = []
			# find all children of our target pid
			Process.clearCache().findOne({ pid: pid }).then (proc) ->
				unless proc then p.reject "no such pid: #{pid}"
				else Process.tree(proc).then (tree) ->
					Process.walk tree, (node) ->
						target_pids.push node.pid # build a list of target children
					if verbose then log "Waiting for targets:", target_pids
					Process.findOne({ ports: port }).then ((owner) ->
						if verbose then log "Port", port, "currently owned by", owner?.pid
						# if there is no owner, or the owner is not one of our targets
						if (not owner) or (not $.matches owner.pid, target_pids)
							# poll again later
							setTimeout poll_port, 300
						else p.resolve owner
			), p.reject

if require.main is module
	return if process.argv.length < 4
	port = parseInt process.argv[2], 10
	pid = parseInt process.argv[3], 10
	Process = require "./process"
	Helpers.portIsOwned(pid, port, 3000).then $.log, console.error.bind console
