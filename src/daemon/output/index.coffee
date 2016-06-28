$ = require 'bling'
Fs = require 'fs'
Stream = require 'stream'
Chalk = require 'chalk'

# wrap a writer to make it ensure that each line has a line-ending
newlineWriter = (s) -> new Stream.Writable write: (data, enc, cb) ->
	data = data.toString("utf8")
	unless data.endsWith '\n'
		data += '\n'
	s.write data, "utf8", cb

drivers = {
	console: class ConsoleDriver
		constructor: -> $.extend @,
			url: "console://"
			stdout: newlineWriter process.stdout
			stderr: newlineWriter process.stderr
			supportsColor: Chalk.supportsColor
	file: class FileDriver
		constructor: (url, parsed) -> $.extend @,
			url: url
			stdout: w = newlineWriter Fs.createWriteStream parsed.path, flags: 'a+'
			stderr: w
			supportsColor: false
	loggly: require('./driver-loggly')
	mongodb: require('./driver-mongodb')
}

emitter = $.EventEmitter()
outputs = $( new ConsoleDriver() )

capacitor = (n, cb) -> -> if --n <= 0 then cb()

writeToAll = (which) -> (data, enc, cb) ->
	emitter.emit which, data, enc
	_cb = capacitor(outputs.length, cb)
	for driver in outputs
		_data = data
		_enc = enc
		if not driver.supportsColor
			_data = Chalk.stripColor data.toString(_enc = "utf8")
		driver[which].write _data, _enc, _cb

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
	getOutputUrls: ->
		outputs.select('url')
	setOutput: (url, tee=false, remove=false) ->
		acted = false
		parsed = $.URL.parse(url)
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
	Output.stdout.write args.map($.toString).join ' '

# Output from the server prepends a timestamp.
# TODO?: use the new prefix level argument in bling 0.9.4?
$.log.enableTimestamps()

$.extend module.exports, Output
