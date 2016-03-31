#!/usr/bin/env coffee

# this is the master process that maintains the herd of processes

# first, we communicate with children via a journal file
# this has the series of configuration commands 
$ = require "bling"
Fs = require "fs"
Net = require "net"
Shell = require "shelljs"
Actions = require("./actions")
{pidFile, socketFile, configFile} = require "./files"
{echo, warn} = require "./output"

unless 'HOME' of process.env
	echo "No $HOME in environment, can't place .shepherd directory."
	process.exit 1

readPid = ->
	try parseInt Fs.readFileSync(pidFile).toString(), 10
	catch then undefined

handleMessage = (msg, client) ->
	# each message invokes an action from a registry
	# defined in src/daemon/actions.coffee
	action = Actions[msg.c]
	return unless action
	doLog = action.onMessage?(msg, client)
	# if this is an action that came from a real client
	# (as opposed to from readLog), and it wants to be,
	# then write it to the configuration log
	if client and doLog
		addToLog(msg)

addToLog = (msg) ->
	echo "Adding message to log...", msg
	Fs.appendFileSync configFile, $.TNET.stringify msg

readLog = ->
	try data = Fs.readFileSync configFile
	catch err
		if err.code is "ENOENT" then return
	
	while data.length > 0
		[msg, data] = $.TNET.parseOne(data)
		echo "Loading message from config:", msg
		handleMessage(msg)

doStop = (exit) ->
	if pid = readPid()
		# send a stop command to all running instances
		echo "[shepd stop] Sending stop action to instances..."
		Actions.stop.onMessage({})
		# give them a little time to exit gracefully
		echo "[shepd stop] Killing daemon pid: #{pid}..."
		# then kill the pid from the pid file (our own?)
		result = Shell.exec "kill #{pid}", { silent: true, async: false }
		if result.stderr.indexOf("No such process") > -1
			echo "[shepd stop] Removing stale PID file and socket."
			try Fs.unlink(pidFile)
			try Fs.unlink(socketFile)
	else
		echo "[shepd stop] Not running."
	if exit
		echo "[shepd stop] Exiting with code 0"
		process.exit 0

switch $(process.argv).last()
	when "stop" then doStop(true)
	when "restart"
		cmd = process.argv.join(' ')
		start = cmd.replace(/ restart$/, " start")
		doStop(false)
		# start a new child that is a copy of ourself
		child = Shell.exec start, { silent: true, async: true }
		child.unref()
		# die
		process.exit 1
	else
		exists = (path) -> return try Fs.statSync(path).isFile() catch then false

		if exists(pidFile)
			echo "[shepd start] Already running as PID:", readPid()
			process.exit 1

		if exists(socketFile)
			echo "[shepd start] Socket file still exists:", socketFile
			process.exit 1

		echo "[shepd start] Writing PID to file:", process.pid
		Fs.writeFileSync(pidFile, process.pid)

		echo "[shepd start] Reading configuration state..."
		readLog()

		echo "[shepd start] Opening socket...", socketFile
		socket = Net.Server().listen({ path: socketFile })
		socket.on 'error', (err) ->
			echo "[shepd start] Failed to open socket:", $.debugStack err
			process.exit 1
		socket.on 'connection', (client) ->
			client.on 'data', (msg) ->
				msg = $.TNET.parse(msg.toString())
				handleMessage(msg, client)

		shutdown = (signal) -> ->
			echo "[shepd] Shutting down...", signal
			try Fs.unlinkSync(pidFile)
			try socket.close()
			if signal isnt 'exit'
				process.exit 0

		for sig in ['SIGINT','SIGTERM','exit']
			process.on sig, shutdown(sig) 

