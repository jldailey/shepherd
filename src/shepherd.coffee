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
verbose = ->
	if Opts.verbose then log.apply null, arguments

if Opts.O is "-"
	try outStr = process.stdout
	catch err then die "Failed to open stdout:", $.debugStack err
else
	try outStr = Fs.createWriteStream Opts.O, { flags: 'a', mode: 0o666, encoding: 'utf8' }
	catch err then die "Failed to open output stream:", $.debugStack err

$.log.out = (a...) ->
	try outStr.write a.map($.toString).join(' ') + "\n", 'utf8'
	catch err then die "Failed to write to log:", $.debugStack err

verbose "Opened output stream."

Helpers  = require './helpers'
Herd     = require './herd'
Validate = require './validate'

if Opts.example
	d = Herd.defaults()
	{ Server, Worker } = require "./child"
	d.servers.push Server.defaults()
	d.workers.push Worker.defaults()
	console.log JSON.stringify d, null, '  '
	process.exit 0

if Opts.P and Opts.daemon # write out a pid file
	verbose "Writing pid file:", Opts.P
	Fs.writeFileSync Opts.P, String process.pid

verbose "Reading config file:", Opts.F
Helpers.readJson(Opts.F).wait (err, config) ->
	if err then die "Failed to open herd file:", Opts.F, $.debugStack err
	errors = Validate.isValidConfig(config)
	if errors.length then die errors.join "\n"
	log "Starting new herd, shepherd PID: " + process.pid
	new Herd(config).start().wait (err) ->
		if err then die "Failed to start herd:", $.debugStack err

