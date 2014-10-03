
$       = require "bling",
Shell   = require "shelljs"
Fs      = require "fs"
Util    = require "util"
Helpers = require './helpers'
Opts    = require './opts'
Herd    = require './herd'
log     = $.logger "[shepherd]"
die     = (a...) ->
	log a...
	process.exit 1

if Opts.defaults
	console.log JSON.stringify Herd.defaults(), null, '  '
	process.exit 0

if Opts.daemon
	do require 'daemon' # fork into the background
	Fs.writeFileSync Opts.P, String process.pid # write out a pid file

if Opts.O isnt "-"
	_slice = Array::slice
	try outStream = Fs.createWriteStream Opts.O, { flags: 'a', mode: 0o666, encoding: 'utf8' }
	catch err then die "Failed to open output stream:", err.stack
	$.log.out = ->
		try outStream.write _slice.call(arguments, 0).join(' ') + "\n", 'utf8'
		catch err then die "Failed to write to log:", err.stack

Helpers.readJson(Opts.F).wait (err, config) ->
	if err then die "Failed to open herd file:", Opts.F, err.stack
	log "Starting new herd, shepherd PID: " + process.pid
	new Herd(config).start().wait (err) ->
		if err then die "Failed to start herd:", err

