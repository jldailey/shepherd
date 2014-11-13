Opts    = require './opts'
if Opts.daemon then require('daemon') { # fork into the background
	stdout: process.stdout, stderr: process.stderr
}
$       = require "bling"
Fs      = require "fs"
log     = $.logger "[shepherd]"
die     = (a...) ->
	log a...
	process.exit 1

if Opts.O is "-"
	try outStr = process.stdout
	catch err then die "Failed to open stdout:", err.stack
else
	try outStr = Fs.createWriteStream Opts.O, { flags: 'a', mode: 0o666, encoding: 'utf8' }
	catch err then die "Failed to open output stream:", err.stack

$.log.out = (a...) ->
	try outStr.write a.map($.toString).join(' ') + "\n", 'utf8'
	catch err then die "Failed to write to log:", err.stack

Helpers = require './helpers'
Herd    = require './herd'

if Opts.example
	d = Herd.defaults()
	{ Server, Worker } = require "./child"
	d.servers.push Server.defaults()
	d.workers.push Worker.defaults()
	console.log JSON.stringify d, null, '  '
	process.exit 0

if Opts.P and Opts.daemon # write out a pid file
	Fs.writeFileSync Opts.P, String process.pid

Helpers.readJson(Opts.F).wait (err, config) ->
	if err then die "Failed to open herd file:", Opts.F, err.stack
	log "Starting new herd, shepherd PID: " + process.pid
	new Herd(config).start().wait (err) ->
		if err then die "Failed to start herd:", err.stack ? err

