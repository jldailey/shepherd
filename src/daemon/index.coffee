#!/usr/bin/env coffee

# this is the master process that maintains the herd of processes

# first, we communicate with children via a journal file
# this has the series of configuration commands 
$ = require "bling"
fs = require "fs"
net = require "net"
Shell = require "shelljs"
codec = $.TNET
echo = $.logger('[shepd]')
actions = require("./actions")

unless 'HOME' of process.env
	echo "No $HOME in environment, can't place .shepherd directory."
	process.exit 1


basePath = "#{process.env.HOME}/.shepherd"
Shell.exec("mkdir -p #{basePath}", { silent: true })

makePath = (parts...) -> [basePath].concat(parts).join "/"
pidFile = makePath "pid"
socketFile = makePath "socket"
configFile = makePath "config"

readPid = ->
	try parseInt fs.readFileSync(pidFile).toString(), 10
	catch then undefined

if $(process.argv).last() is "stop"
	if pid = readPid()
		result = Shell.exec "kill #{pid}", { silent: true }
		if result.stderr.indexOf("No such process") > -1
			echo "Removing stale PID file and socket."
			try fs.unlink(pidFile)
			try fs.unlink(socketFile)
	else
		echo "Not running."
	process.exit 0

exists = (path) -> return try fs.statSync(path).isFile() catch then false

if exists(pidFile)
	echo "Already running as PID:", readPid()
	process.exit 1

if exists(socketFile)
	echo "Socket file still exists:", socketFile
	process.exit 1

echo "Writing PID to file:", process.pid
fs.writeFileSync(pidFile, process.pid)

echo "Opening socket...", socketFile
socket = net.Server().listen({ path: socketFile })
socket.on 'error', (err) ->
	echo "Failed to open socket:", $.debugStack err
	process.exit 1
socket.on 'connection', (client) ->
	client.on 'data', (msg) ->
		msg = codec.parse(msg.toString())
		# each message invokes an action from a registry
		# defined in src/daemon/actions.coffee
		actions[msg.c]?(msg, client)

shutdown = (signal) -> ->
	echo "Shutting down...", signal
	try fs.unlinkSync(pidFile)
	try socket.close()
	if signal isnt 'exit'
		process.exit 0

for sig in ['SIGINT','SIGTERM','exit']
	process.on sig, shutdown(sig) 

