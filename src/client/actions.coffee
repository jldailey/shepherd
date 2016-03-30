$ = require 'bling'
{yesNo, formatUptime} = require "./format"

module.exports = {
	start: {
		options: [
			[ "--instance <id>", "Start one particular instance." ]
			[ "--group <group>", "Start all instances in a group." ]
		]
		toMessage: (cmd) ->
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
		onResponse: (resp) ->
			resp.unshift ["Instance", "PID", "Port", "Uptime", "Healthy"]
			for line,i in resp
				if i > 0
					line[2] ?= "-"
					line[3] = formatUptime line[3]
					line[4] = if line[4] is undefined then "?" else yesNo line[4]
				$.log line.map((item) -> $.padLeft String(item ? ''), 14).join ''
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
}
