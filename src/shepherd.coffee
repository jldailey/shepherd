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

outStr = {
	write: (data, enc) -> # default output stream
		console.log data
}

if Opts.O is "-"
	try outStr = process.stdout
	catch err then die "Failed to open stdout:", $.debugStack err
else
	try outStr = Fs.createWriteStream Opts.O, { flags: 'a', mode: 0o666, encoding: 'utf8' }
	catch err then die "Failed to open output stream:", $.debugStack err

$.log.out = (a...) ->
	try outStr.write a.map($.toString).join(' ') + "\n", 'utf8'
	catch err then die "Failed to write to log:", $.debugStack err

$.log.enableTimestamps()

verbose "Opened output stream to: #{Opts.O}"

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

if Opts.P # write out a pid file
	verbose "Writing pid file:", Opts.P
	Fs.writeFileSync Opts.P, String process.pid

verbose "Reading config file:", Opts.F
Helpers.readJson(Opts.F).wait (err, config) ->
	if err then die "Failed to open herd file:", Opts.F, $.debugStack err
	config = Herd.defaults(config)
	errors = Validate.isValidConfig(config)
	if errors.length then die errors.join "\n"
	log "Starting new herd, shepherd PID: " + process.pid
	if config.loggly?.enabled
		outStr = require("./loggly").createWriteStream {
			token: config.loggly.token
			subdomain: config.loggly.subdomain
			tags: config.loggly.tags ? []
			json: config.loggly.json ? false
		}
	new Herd(config).start().wait (err) ->
		if err then die "Failed to start herd:", $.debugStack err

