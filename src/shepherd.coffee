
$       = require "bling",
Shell   = require "shelljs"
Fs      = require "fs"
Util    = require "util"
Helpers = require './helpers'
Opts    = require './opts'
Herd    = require './herd'
log     = $.logger "[shepherd]"

if Opts.defaults
	console.log JSON.stringify Herd.defaults(), null, '  '
	process.exit 0

if Opts.daemon
	do require 'daemon' # fork into the background
	Fs.writeFileSync Opts.P, String process.pid # write out a pid file

if Opts.O isnt "-"
	_slice = Array::slice
	_die = -> console.error.apply console, arguments; process.exit 1
	try outStream = Fs.createWriteStream Opts.O, { flags: 'a', mode: 0o666, encoding: 'utf8' }
	catch err then _die "Failed to open output stream to", Opts.O, err.stack
	$.log.out = ->
		try outStream.write _slice.call(arguments, 0).join(' ') + "\n", 'utf8'
		catch err then _die "Failed to write to", Opts.O, err.stack

Helpers.readJson(Opts.F).then ((config) ->
	log "Starting new herd, shepherd PID: " + process.pid
	new Herd(config).start()
), (err) ->
	log "Failed to open herd file:", Opts.F, err.stack
	process.exit 1

