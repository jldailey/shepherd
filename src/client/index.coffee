#!/usr/bin/env coffee

program = require("commander")
net = require "net"
$ = require 'bling'
echo = $.logger('[shepherd]')

# read package.json
pkg = JSON.parse require("fs").readFileSync __dirname + "/../../package.json"

# set the version based on package.json
program.version(pkg.version).usage("<command> [options]")

basePath = "#{process.env.HOME}/.shepherd"
socketFile = [basePath, "socket"].join "/"

# import the action registry
Actions = require("../actions")

read_tnet_stream = (s, cb) ->
	buf = ""
	s.on 'data', (data) ->
		buf += data.toString("utf8")
		while buf.length > 0
			[ item, rest ] = $.TNET.parseOne( buf )
			break if rest.length is buf.length # if we didn't consume anything, wait for the next data to resume parsing
			buf = rest
			cb item
	null

# every action passes command-line objects to the server
send_command = (cmd) ->
	return unless cmd._name of Actions
	action = Actions[cmd._name]

	socket = net.connect({ path: socketFile})
	socket.on 'error', (err) -> # probably daemon is not running, should start it
		if err.code is 'ENOENT'
			echo "Shepherd master daemon (shepd) is not running."
		else
			echo "socket.on 'error', ->", $.debugStack err

	socket.on 'connect', ->
		msg = action.toMessage cmd
		bytes = $.TNET.stringify msg
		socket.write bytes, ->
			# some commands wait for a response
			if 'onConnect' of action
				action.onConnect(socket)
			if 'onResponse' of action
				timeout = $.delay 1000, ->
					echo "Timed-out waiting for a response from the server."
					socket.end()
				# we use a TNET socket wrapper,
				# which keeps buffering data events until
				# it can parse one object from the stream and continue.
				read_tnet_stream socket, (item) ->
					timeout.cancel()
					action.onResponse item, socket
			else socket.end()

# use the action registry to set command-line options
for name, action of Actions
	p = program.command(name)
	for option in action.options ? []
		p.option option[0], option[1], option[2]
	p.action send_command

# parse the command line and invoke the action handlers
$.log.disableTimestamps()
echo ["> shepherd"].concat(process.argv.slice(2)).join ' '
program.parse process.argv

