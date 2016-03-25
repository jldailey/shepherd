
# this is the master process that maintains the herd of processes

# first, we communicate with children via a journal file
# this has the series of configuration commands 
$ = require "bling"
fs = require "fs"
net = require "net"
Shell = require "shelljs"
codec = $.TNET
env = process.env
echo = $.logger('[shepd]')

unless 'HOME' of env
	echo "No $HOME in environment, can't find .shepherd directory."
	process.exit 1

basePath = "#{env.HOME}/.shepherd"
Shell.exec("mkdir -p #{basePath}", { silent: true })

pidFile = [basePath, "pid"].join "/"
socketFile = [basePath, "socket"].join "/"

readPid = ->
	try parseInt fs.readFileSync(pidFile).toString(), 10
	catch then null

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

# TODO: enable once we are building to js, daemon module doesnt support coffee-script
# require("daemon") { stdout: process.stdout, stderr: process.stderr }

echo "Writing PID to file:", process.pid
fs.writeFileSync(pidFile, process.pid)

echo "Opening socket...", socketFile
socket = net.Server().listen({ path: socketFile })
socket.on 'error', (err) ->
	echo "Failed to open socket:", $.debugStack err
socket.on 'connection', (client) ->
	client.on 'data', (msg) ->
		msg = codec.parse(msg.toString())
		({
			start: actionStart = ->
			stop: actionStop = ->
			restart: actionRestart = ->
			status: actionStatus
			add: actionAdd
			scale: actionScale = ->
		})[msg.c]?(msg, client)

class Group
	constructor: (@name, @cd, @exec, @n, @port) ->
		@procs = $.range(0,@n).map (i) =>
			new Proc "#{@name}-#{i}", @cd, @exec, @port + i, @

class Proc
	constructor: (@id, @cd, @exec, @port, @group) ->
		@started = undefined
		@pid = undefined
		@autoRestart = true
	start: ->
		@proc = Shell.exec @exec, { cwd: @cd, env: { PORT: @port }, silent: true, async: true }
		@started = $.now
		@proc.stdout.on 'data', (data) ->
			process.stdout.write data
		@proc.stderr.on 'data', (data) ->
			process.stderr.write data
		@proc.on 'exit', =>
			@started = undefined
			if @autoRestart
				$.immediate => @start()

groups = {}

actionAdd = (msg) ->
	unless msg.g and msg.g.length
		echo "--group is required with 'add'"
		return
	if msg.g of groups
		echo "ignoring add request for existing group"
	else groups[msg.g] = new Group(msg.g, msg.cd, msg.exec, msg.n, msg.p)


actionStatus = (msg, client) ->
	echo "Handling status request..."
	$.valuesOf(groups).each (group) ->
		for proc in group.procs
			uptime = if proc.started then $.now - proc.started else 0
			uptime = formatUptime(uptime)
			output.push [ proc.id, proc.pid ? '-', proc.port, uptime ]
	client.write codec.stringify(output)

shutdown = (signal) -> ->
	echo "Shutting down...", signal
	try fs.unlinkSync(pidFile)
	try socket.close()

for sig in ['SIGINT','SIGTERM','exit']
	process.on sig, shutdown(sig) 
