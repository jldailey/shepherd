Opts    = require './opts'
if Opts.daemon
	do require 'daemon' # fork into the background
$       = require "bling",
Shell   = require "shelljs"
Fs      = require "fs"
Util    = require "util"
Helpers = require './helpers'
Herd    = require './herd'
log     = $.logger "[shepherd]"
die     = (a...) ->
	console.log a...
	process.exit 1

if Opts.example
	d = Herd.defaults()
	{ Server, Worker } = require "./child"
	d.servers.push Server.defaults()
	d.workers.push Worker.defaults()
	console.log JSON.stringify d, null, '  '
	process.exit 0


if Opts.P # write out a pid file
	Fs.writeFileSync Opts.P, String process.pid

if Opts.O is "-"
	try outStream = process.stdout
	catch err then die "Failed to open stdout:", err.stack
else
	try outStream = Fs.createWriteStream Opts.O, { flags: 'a', mode: 0o666, encoding: 'utf8' }
	catch err then die "Failed to open output stream:", err.stack

$.log.out = (a...) ->
	try outStream.write a.join(' ') + "\n", 'utf8'
	catch err then die "Failed to write to log:", err.stack

Helpers.readJson(Opts.F).wait (err, config) ->
	if err then die "Failed to open herd file:", Opts.F, err.stack
	log "Starting new herd, shepherd PID: " + process.pid
	new Herd(config).start().wait (err) ->
		if err then die "Failed to start herd:", err.stack ? err

