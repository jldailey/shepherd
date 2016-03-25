program = require("commander")
net = require "net"
$ = require 'bling'
echo = $.logger('[client]')

# read package.json
pkg = JSON.parse require("fs").readFileSync __dirname + "/../package.json"

# set the version based on package.json
program.version(pkg.version).usage("<command> [options]")

codec = $.TNET # slower than JSON but allows sending nulls, custom types, etc

basePath = "#{process.env.HOME}/.shepherd"
socketFile = [basePath, "socket"].join "/"

actions = {
	start: {
		options: [
			[ "--instance <id>", "Start one particular instance." ]
			[ "--group <group>", "Start all instances in a group." ]
		]
		toMessage: (cmd) ->
			$.log "command", cmd
			{ c: 'start', g: cmd.group, i: cmd.instance }
	}
	stop: {
		options: [
			[ "--instance <id>", "Stop one particular instance." ]
			[ "--group <group>", "Stop all instances in a group." ]
		]
		toMessage: (cmd) ->
			{ c: 'stop', g: cmd.group, i: cmd.instance }
	}
	restart: {
		options: [
			[ "--instance <id>", "Restart one particular instance." ]
			[ "--group <group>", "Restart all instances in a group." ]
		]
		toMessage: (cmd) ->
			{ c: 'restart', g: cmd.group, i: cmd.instance }
	}
	status: {
		toMessage: (cmd) ->
			{ c: 'status' }
	}
	add: {
		options: [
			[ "--group <group>", "Name of the group to create." ]
			[ "--cd <path>", "The working directory to spawn processes in." ]
			[ "--exec <script>", "Any shell command, e.g. 'node app.js'." ]
			[ "-n,--count <n>", "The starting size of the group." ]
			[ "-p,--port <port>", "If specified, set PORT in env for each child, incrementing port each time." ]
		]
		toMessage: (cmd) ->
			{ c: 'add', g: cmd.group, cd: cmd.cd, exec: cmd.exec, n: parseInt(cmd.count,10), p: parseInt(cmd.port,10) }
	}
	disable: {
		options: [
			[ "--instance <id>", "Disable (stop and don't restart) one instance." ]
			[ "--group <group>", "Disable all instances in a group." ]
		]
		toMessage: (cmd) ->
			{ c: 'disable', g: cmd.group, i: cmd.instance }
	}
	enable: {
		options: [
			[ "--instance <id>", "Enable (stop and don't restart) one instance." ]
			[ "--group <group>", "Enable all instances in a group." ]
		]
		toMessage: (cmd) ->
			{ c: 'enable', g: cmd.group, i: cmd.instance }


}

# once command strings are parsed, they get sent to the daemon
send_command = (cmd) ->
	return unless cmd._name of actions

	socket = net.connect({ path: socketFile})
	socket.on 'error', (err) -> # probably daemon is not running, should start it
		$.log "socket.on 'error', ->", $.debugStack err

	socket.on 'connect', ->
		
		socket.write bytes = codec.stringify(actions[cmd._name].toMessage(cmd)), ->
			# some commands wait for a response
			if cmd._name in ['status']
				echo "Waiting for response..."
				socket.on 'data', (resp) ->
					for row in codec.parse resp.toString()
						line = ""
						for item in row
							line += $.padLeft String(item ? ''), 14
						$.log line
					socket.end()
			else socket.end()
		echo "Wrote bytes:", bytes

for name, action of actions
	p = program.command(name)
	for option in action.options ? []
		p.option option[0], option[1]
	p.action send_command

# this will parse the command line and invoke the action handlers above
program.parse process.argv


yesNo = (v) -> if v then "yes" else "no"
secs = 1000
mins = 60 * secs
hours = 60 * mins
days = 24 * hours
weeks = 7 * days
formatUptime = (ms) ->
	w = Math.floor(ms / weeks)
	t = ms - (w * weeks)
	d = Math.floor(t / days)
	t = t - (d * days)
	h = Math.floor(t / hours)
	t = t - (h * hours)
	m = Math.floor(t / mins)
	t = t - (m * mins)
	s = Math.floor(t / secs)
	t = t - (s * secs)
	ret = $("w", "d", "h", "m", "s")
		.weave($ w, d, h, m, s)
		.join('')
		.replace(/^(0[wdhm])*/,'')
	ret
