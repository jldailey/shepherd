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
	warn: warn = (args...) ->
		echo Chalk.yellow("[warn]"), args...
	echo: echo = (args...) ->
		line = args.map($.toString).join ' '
		Output.stdout.write line
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
		parsed = $.URL.parse(url)
		p = parsed.protocol
		if remove
			acted = false
			while (i = outputs.select('url').indexOf url) > -1
				outputs.splice i, 1
				acted = true
			return acted
		else if d = drivers[p]
			if outputs.select('url').indexOf(url) > -1
				# warn "Ignoring request to add output: #{url} (reason: already added)"
				return false
			driver = new d(url, parsed)
			if tee then outputs.push driver
			else
				outputs.select('close').call()
				outputs.clear().push driver
			return true
		else
			warn "No such output driver: "+p
		false
	stdout: new Stream.Writable write: writeToAll 'stdout'
	stderr: new Stream.Writable write: writeToAll 'stderr'
}

$.log.out = Output.echo
$.extend module.exports, Output
