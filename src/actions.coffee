
$ = require 'bling'
Chalk = require 'chalk'
Output = require "./daemon/output"
int = (n) -> parseInt((n ? 0), 10)
{yesNo, formatUptime, trueFalse} = require "./format"

healthSymbol = (v) -> switch v
	when undefined then Chalk.yellow "?"
	when true then Chalk.green "\u2713"
	when false then Chalk.red "x"

{ Groups, addGroup, removeGroup, simpleAction } = require "./daemon/groups"

module.exports = {

	# Adding a group
	add: {
		options: [
			[ "--group <group>", "Name of the group to create." ]
			[ "--cd <path>", "The working directory to spawn processes in." ]
			[ "--exec <script>", "Any shell command, e.g. 'node app.js'." ]
			[ "--count <n>", "The starting size of the group.", int ]
			[ "--port <port>", "If specified, set PORT in env for each child, incrementing port each time.", int ]
		]
		toMessage: (cmd) ->
			{ c: 'add', g: cmd.group, d: cmd.cd, x: cmd.exec, n: cmd.count, p: cmd.port }
		onMessage: (msg, client) ->
			unless msg.g and msg.g.length
				warn "--group is required with 'add'"
				return false
			return addGroup(msg.g, msg.d, msg.x, msg.n, msg.p)
	}

	# Removing a group
	remove: {
		options: [
			[ "--group <group>", "Name of the group to create." ]
		]
		toMessage: (cmd) -> { c: 'remove', g: cmd.group }
		onMessage: (msg, client) -> removeGroup msg.g
	}

	# Start a group or instance.
	start: {
		options: [
			[ "--instance <id>", "Start one particular instance." ]
			[ "--group <group>", "Start all instances in a group." ]
		]
		toMessage: (cmd) -> { c: 'start', g: cmd.group, i: cmd.instance }
		onMessage: simpleAction 'start', false
	}

	# Stop a group or instance.
	stop: {
		options: [
			[ "--instance <id>", "Stop one particular instance." ]
			[ "--group <group>", "Stop all instances in a group." ]
		]
		toMessage: (cmd) -> { c: 'stop', g: cmd.group, i: cmd.instance }
		onMessage: simpleAction 'stop', false
	}

	# Restart a group or instance.
	restart: {
		options: [
			[ "--instance <id>", "Restart one particular instance." ]
			[ "--group <group>", "Restart all instances in a group." ]
		]
		toMessage: (cmd) -> { c: 'restart', g: cmd.group, i: cmd.instance }
		onMessage: simpleAction 'restart', false
	}

	# Get the status of everything.
	status: {
		toMessage: (cmd) -> { c: 'status' }
		onResponse: (resp, socket) ->
			$.log "Outputs"
			$.log "-------"
			for output in resp.outputs
				$.log "\tURL: " + output
			$.log ""
			resp.procs.unshift ["--------", "---", "----", "------", "-------"]
			resp.procs.unshift ["Instance", "PID", "Port", "Uptime", "Healthy"]
			for line,i in resp.procs
				if i > 1
					line[1] ?= Chalk.red "-"
					line[3] = formatUptime line[3]
					line[4] = healthSymbol line[4]
				$.log ( ($.padLeft String(item ? ''), 14) for item,i in line).join ''
			socket.end()

		onMessage: (msg, client) ->
			output = {
				procs: []
				outputs: Output.getOutputUrls()
			}
			Groups.forEach (group) ->
				for proc in group.procs
					output.procs.push [ proc.id, proc.proc?.pid, proc.port, proc.uptime, proc.healthy ]
			client.write $.TNET.stringify output
			return false
	}

	# Tail the current output.
	tail: {
		toMessage: (cmd) -> { c: 'tail' }
		onConnect: (socket) ->
			$.log "Piping socket to stdout..."
			socket.pipe(process.stdout)
			process.on 'SIGINT', -> try socket.end()
		onMessage: (msg, client) ->
			$.log "Calling Output.tail...", msg
			Output.tail(client)
			return false
	}

	# Disable a group or instance.
	disable: {
		options: [
			[ "--instance <id>", "Disable (stop and don't restart) one instance." ]
			[ "--group <group>", "Disable all instances in a group." ]
		]
		toMessage: (cmd) -> { c: 'disable', g: cmd.group, i: cmd.instance }
		onMessage: simpleAction 'disable', true
	}

	# Enable a group or instance.
	enable: {
		options: [
			[ "--instance <id>", "Enable (stop and don't restart) one instance." ]
			[ "--group <group>", "Enable all instances in a group." ]
		]
		toMessage: (cmd) -> { c: 'enable', g: cmd.group, i: cmd.instance }
		onMessage: simpleAction 'enable', true
	}

	# Scale the number of instance in a group up/down.
	scale: {
		options: [
			[ "--group <group>", "Which group to scale." ]
			[ "--count <n>", "How many processes should be running.", int ]
		]
		toMessage: (cmd) -> { c: 'scale', g: cmd.group, n: cmd.count }
		onMessage: (msg, client) ->
			unless msg.g and msg.g.length
				warn "--group is required with 'scale'"
				return false
			unless Groups.has(msg.g)
				warn "Unknown group name passed to --group ('#{msg.g}')"
				return false
			group = Groups.get(msg.g)
			group.scale(msg.n)
			return true
	}

	# Add/remove log output destinations.
	log: {
		options: [
			[ "--url <url>", "Send output to this destination. Supports protocols: console, file, loggly, and mongodb." ]
			[ "--tee", "Send to this destination, in addition to other destinations." ]
			[ "--remove", "Remove one url as a log destination." ]
		]
		toMessage: (cmd) -> { c: 'log', u: cmd.url, t: trueFalse cmd.tee, r: trueFalse cmd.remove }
		onMessage: (msg) ->
			console.log "setOutput", msg
			return Output.setOutput msg.u, msg.t, msg.r
	}

	# Add/remove a health check.
	health: {
		options: [
			[ "--group <group>", "Check all processes in this group." ]
			[ "--path <path>", "Will request http://localhost:port/<path> and check the response." ]
			[ "--status <code>", "Check the status code of the response."]
			[ "--contains <text>", "Check that the response contains some bit of text."]
			[ "--interval <secs>", "How often to run a check." ]
			[ "--timeout <ms>", "Fail if response is slower than this." ]
			[ "--delete", "Remove a health check." ]
			[ "--pause", "Temporarily pause a health check." ]
			[ "--resume", "Resume a health check after pausing." ]
		]
		toMessage: (cmd) -> {
			c: 'health',
			g: cmd.group,
			p: cmd.path,
			s: int cmd.status,
			i: int cmd.interval,
			o: int cmd.timeout,
			t: cmd.contains,
			d: trueFalse cmd.delete,
			z: trueFalse cmd.pause,
			r: trueFalse cmd.resume
		onMessage: (msg) -> return switch
			when msg.d then Health.unmonitor msg.u
			when msg.z then Health.pause msg.u
			when msg.r then Health.resume msg.u
			else
				return false unless Groups.has(msg.g)
				Health.monitor Groups.get(msg.g), msg.p, msg.i, msg.s, msg.t, msg.o
		}
	}

	# Configure nginx integration.
	nginx: {
		options: [
			[ "--file <file>", "Auto-generate an nginx file with an upstream definition for each group."]
			[ "--reload <cmd>", "What command to run in order to cause nginx to reload."]
			[ "--disable", "Don't generate files or reload nginx." ]
		]
		toMessage: (cmd) -> { c: 'nginx', f: cmd.config, r: cmd.reload, d: trueFalse cmd.disable }
	}

}
