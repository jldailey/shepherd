#!/usr/bin/env coffee
#
# Objective: shep a herd of wild processes

$ = require "bling"
Shell = require "shelljs"
Fs = require "fs"
Opts = require "commander"
Http = require 'http'

$.Promise.jsonFile = (file, p = $.Promise()) ->
	p.wait (err) ->
		if err then $.log "jsonFile(#{file}) failed:", err
	Fs.readFile file, (err, data) ->
		return p.fail(err) if err
		try p.finish JSON.parse data
		catch err
			p.fail err
	p

log = $.logger "[shepherd]"
log "Starting as PID:", process.pid

$.Promise.jsonFile("package.json").then (pkg) ->
	Opts.version(pkg.version)
		.option('-h [file]', "The .herd file to load", ".herd")
		.parse(process.argv)
	$.Promise.jsonFile(Opts.h).then (herd) ->
		log "Starting HTTP server..."
		httpServer = Http.createServer((req, res) ->
			res.statusCode = 200
			res.end("Thanks for coming.")
		)
		httpServer.listen herd.httpPort, (err) ->
			if err
				log "Error:", err
				process.exit(1)
			else log "HTTP Server ready for webhooks"

		children = []

		launch = (i) ->
			port = Opts.port + i
			cmd_string = "PORT=#{port} #{Opts.command}"
			start_attempts = 0
			restartTimeout = null
			children.push child = Shell.exec cmd_string, { silent: true, async: true }, (code) ->
				log "Child PID: #{child.pid} Exited with code: ", code
				for c,j in children
					if c.pid is child.pid
						children.splice j, 1
						break

				if code is Opts.restartCode and (++start_attempts) < Opts.maxRestart
					launch(i)
				else if children.length is 0
					log "All children exited gracefully, shutting down (no flock to tend)."
					process.exit(0)
				else log "Still #{children.length} children running"
				clearTimeout restartTimeout
				restartTimeout = setTimeout (-> start_attempts = 0), Opts.restartTimeout
			child.stdout.on "data", $.logger "[child-#{child.pid}]"
			child.stderr.on "data", $.logger "[child-#{child.pid}(stderr)]"

		launch(i) for i in [0...parseInt(Opts.number, 10)] by 1
