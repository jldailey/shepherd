#!/usr/bin/env coffee

program = require("commander")
net = require "net"
$ = require 'bling'
echo = $.logger('[client]')

# read package.json
pkg = JSON.parse require("fs").readFileSync __dirname + "/../../package.json"

# set the version based on package.json
program.version(pkg.version).usage("<command> [options]")

codec = $.TNET # slower than JSON but allows sending nulls, custom types, etc

basePath = "#{process.env.HOME}/.shepherd"
socketFile = [basePath, "socket"].join "/"

actions = require("./actions")

# once command strings are parsed, they get sent to the daemon
send_command = (cmd) ->
	return unless cmd._name of actions
	action = actions[cmd._name]

	socket = net.connect({ path: socketFile})
	socket.on 'error', (err) -> # probably daemon is not running, should start it
		$.log "socket.on 'error', ->", $.debugStack err

	socket.on 'connect', ->
		message = codec.stringify action.toMessage cmd
		
		socket.write message, ->
			# some commands wait for a response
			if 'onResponse' of action
				echo "Waiting for response..."
				socket.on 'data', (resp) ->
					action.onResponse codec.parse resp.toString()
					socket.end()
			else socket.end()
		echo "Wrote message:", message

for name, action of actions
	p = program.command(name)
	for option in action.options ? []
		p.option option[0], option[1]
	p.action send_command

# this will parse the command line and invoke the action handlers above
program.parse process.argv

