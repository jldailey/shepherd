#!/usr/bin/env coffee

program = require("commander")
net = require "net"
$ = require 'bling'
echo = $.logger('[shepherd]')

# read package.json
pkg = JSON.parse require("fs").readFileSync __dirname + "/../../package.json"

# set the version based on package.json
program.version(pkg.version).usage("<command> [options]")

codec = $.TNET # slower than JSON but allows sending nulls, custom types, etc

basePath = "#{process.env.HOME}/.shepherd"
socketFile = [basePath, "socket"].join "/"

# import the action registry
actions = require("./actions")

# every action passes command-line objects to the server
send_command = (cmd) ->
	return unless cmd._name of actions
	action = actions[cmd._name]

	socket = net.connect({ path: socketFile})
	socket.on 'error', (err) -> # probably daemon is not running, should start it
		if err.code is 'ENOENT'
			echo "Server is not running."
		else
			echo "socket.on 'error', ->", $.debugStack err

	socket.on 'connect', ->
		socket.write codec.stringify(action.toMessage cmd), ->
			# some commands wait for a response
			if 'onConnect' of action
				action.onConnect(socket)
			if 'onResponse' of action
				delay = $.delay 1000, ->
					echo "Timed-out waiting for a response from the server."
					socket.end()
				socket.on 'data', (resp) ->
					delay.cancel()
					action.onResponse codec.parse resp.toString()
					socket.end()
			else socket.end()

# use the action registry to set command-line options
for name, action of actions
	p = program.command(name)
	for option in action.options ? []
		p.option option[0], option[1]
	p.action send_command

# parse the command line and invoke the action handlers
echo process.argv.join ' '
program.parse process.argv

