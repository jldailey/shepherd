$ = require 'bling'
Fs = require 'fs'
Chalk = require 'chalk'
Stream = require 'stream'

drivers = {
	console: class ConsoleDriver
		constructor: -> $.extend @,
			url: "console://"
			stdout: process.stdout
			stderr: process.stderr
			supportsColor: Chalk.supportsColor
			needsNewline: true
	file: class FileDriver
		constructor: (url, parsed) -> $.extend @,
			url: url
			stdout: w = Fs.createWriteStream parsed.path, flags: 'a+'
			stderr: w
			supportsColor: false
			needsNewline: true
	loggly: require('./driver-loggly')
	mongodb: require('./driver-mongodb')
}

emitter = $.EventEmitter()
outputs = $( new ConsoleDriver() )

# must be called n times and then cb() gets called
capacitor = (n, cb) -> -> if --n <= 0 then cb()

writeToAll = (which) -> (data, enc, cb) ->
	emitter.emit which, data, enc
	data = data.toString("utf8")
	enc = "utf8"
	_stripped_data = null # cache of data with color removed, if at least one driver needs it
	_cb = capacitor(outputs.length, cb)
	for driver in outputs
		_data = data
		unless driver.supportsColor
			_data = (_stripped_data or= Chalk.stripColor data)
		if driver.needsNewline
			_data += "\n" unless _data.endsWith("\n")
		driver[which].write _data, enc, _cb
	null

Output = {
	tail: (client) ->
		emitter.on 'stdout', send = client.write.bind client
		emitter.on 'stderr', send
		client.on 'close', cleanup = ->
			emitter.removeListener 'stdout', send
			emitter.removeListener 'stderr', send
			try client.close()
		client.on 'disconnect', cleanup
		client.on 'error', cleanup
	getOutputUrls: -> outputs.select('url')
	setOutput: (url, tee=false, remove=false) ->
		acted = false
		parsed = $.URL.parse(url) or {}
		p = parsed.protocol
		if remove
			while (i = outputs.select('url').indexOf url) > -1
				outputs.splice i, 1
				acted = true
		else if (d = drivers[p]) and not outputs.select('url').contains(url)
			driver = new d(url, parsed)
			if tee then outputs.push driver
			else
				outputs.select('close').call()
				outputs.clear().push driver
			acted = true
		else
			$.log "[warning] Did not add output: #{url} - " + switch
				when not p? then "No valid protocol."
				when not drivers[p] then "No driver for protocol."
				when outputs.select('url').contains(url) then "Already added."
				else ""
		return acted
	stdout: new Stream.Writable write: writeToAll 'stdout'
	stderr: new Stream.Writable write: writeToAll 'stderr'
}

# Connect $.log to the Output driver system.
$.log.out = (args...) ->
	str = args.map($.toString).join ' '
	Output.stdout.write str

# Output from the server prepends a timestamp.
# TODO?: use the new prefix level argument in bling 0.9.4?
$.log.enableTimestamps()

$.extend module.exports, Output
