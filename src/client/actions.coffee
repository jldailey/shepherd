$ = require 'bling'
Chalk = require 'chalk'
{yesNo, formatUptime, trueFalse } = require "./format"

int = (n) -> parseInt n, 10

module.exports = Actions = {
	start: {
		options: [
			[ "--instance <id>", "Start one particular instance." ]
			[ "--group <group>", "Start all instances in a group." ]
		]
		toMessage: (cmd) -> { c: 'start', g: cmd.group, i: cmd.instance }
		onResponse: statusResponse
	}
	stop: {
		options: [
			[ "--instance <id>", "Stop one particular instance." ]
			[ "--group <group>", "Stop all instances in a group." ]
		]
		toMessage: (cmd) -> { c: 'stop', g: cmd.group, i: cmd.instance }
		onResponse: statusResponse
	}
	restart: {
		options: [
			[ "--instance <id>", "Restart one particular instance." ]
			[ "--group <group>", "Restart all instances in a group." ]
		]
		toMessage: (cmd) -> { c: 'restart', g: cmd.group, i: cmd.instance }
		onResponse: statusResponse
	}
	status: {
		toMessage: (cmd) -> { c: 'status' }
		onResponse: statusResponse = (resp) ->
			$.log "Outputs"
			$.log "-------"
			for output in resp.outputs
				$.log "\tURL: " + output
			$.log ""
			resp.procs.unshift ["--------", "---", "----", "------", "-------"]
			resp.procs.unshift ["Instance", "PID", "Port", "Uptime", "Healthy"]
			for line,i in resp.procs
				# we must use this awkward color array to work-around the fact that $.padLeft will include the color codes in the string width and won't pad
				colors = $.zeros(5).map -> 'white'
				if i > 1
					line[1] ?= "-"
					colors[1] = if line[1] is '-' then 'red' else 'green'
					line[3] = formatUptime line[3]
					line[4] = if line[4] is undefined then "?" else yesNo line[4]
					if line[4] is "?"
						colors[4] = "yellow"
				$.log ( Chalk[colors[i]]($.padLeft String(item ? ''), 14) for item,i in line).join ''
	}
	tail: {
		toMessage: (cmd) -> { c: 'tail' }
		onConnect: (socket) -> socket.pipe(process.stdout)
	}
	add: {
		options: [
			[ "--group <group>", "Name of the group to create." ]
			[ "--cd <path>", "The working directory to spawn processes in." ]
			[ "--exec <script>", "Any shell command, e.g. 'node app.js'." ]
			[ "--count <n>", "The starting size of the group." ]
			[ "--port <port>", "If specified, set PORT in env for each child, incrementing port each time." ]
		]
		toMessage: (cmd) -> { c: 'add', g: cmd.group, d: cmd.cd, x: cmd.exec, n: int cmd.count, p: int cmd.port }
		onResponse: statusResponse
	}
	disable: {
		options: [
			[ "--instance <id>", "Disable (stop and don't restart) one instance." ]
			[ "--group <group>", "Disable all instances in a group." ]
		]
		toMessage: (cmd) -> { c: 'disable', g: cmd.group, i: cmd.instance }
		onResponse: statusResponse
	}
	enable: {
		options: [
			[ "--instance <id>", "Enable (stop and don't restart) one instance." ]
			[ "--group <group>", "Enable all instances in a group." ]
		]
		toMessage: (cmd) -> { c: 'enable', g: cmd.group, i: cmd.instance }
		onResponse: statusResponse
	}
	log: {
		options: [
			[ "--url <url>", "Send output to this destination. Supports protocols: console, file, loggly, and mongodb." ]
			[ "--tee", "Send to this destination, in addition to other destinations." ]
			[ "--remove", "Remove one url as a log destination." ]
		]
		toMessage: (cmd) -> { c: 'log', u: cmd.url, t: trueFalse cmd.tee, r: trueFalse cmd.remove }
	}
	health: {
		options: [
			[ "--url <url>", "Make an HTTP request to this address."]
			[ "--status <code>", "Check the status code of the response."]
			[ "--contains <text>", "Check that the response contains some bit of text."]
			[ "--interval <secs>", "How often to run a check." ]
			[ "--delete", "Remove a health check." ]
			[ "--pause", "Temporarily pause a health check." ]
			[ "--resume", "Resume a health check after pausing." ]
		]
		toMessage: (cmd) -> { c: 'health', u: cmd.url, s: int cmd.status, t: cmd.contains, i: int cmd.interval, p: trueFalse cmd.pause, r: trueFalse cmd.resume, d: trueFalse cmd.delete }
	}
	nginx: {
		options: [
			[ "--file <file>", "Auto-generate an nginx file with an upstream definition for each group."]
			[ "--reload <cmd>", "What command to run in order to cause nginx to reload."]
			[ "--disable", "Don't generate files or reload nginx." ]
		]
		toMessage: (cmd) -> { c: 'nginx', f: cmd.config, r: cmd.reload, d: trueFalse cmd.disable }
	}
}
