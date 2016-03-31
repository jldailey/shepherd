$ = require 'bling'
Fs = require 'fs'
Stream = require 'stream'
Chalk = require 'chalk'

drivers = {
	console: class ConsoleDriver
		constructor: ->
			$.extend @,
				url: "console://"
				stdout: process.stdout
				stderr: process.stderr
				supportsColor: Chalk.supportsColor
	file: class FileDriver
		constructor: (url) ->
			$.extend @,
				url: $.URL.stringify(url)
				stdout: f = Fs.createWriteStream(url.path)
				stderr: f
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
		driver[which].write data, enc, _cb

module.exports = Output = {
	warn: warn = (args...) ->
		echo Chalk.yellow "[warn] " + args.map($.toString).join ' '
	echo: echo = (args...) ->
		line = args.map($.toString).join ' '
		unless line.endsWith('\n')
			line += '\n'
		try Output.stdout.write line
		catch err
			console.log $.debugStack err
			process.exit 1
	tail: (client) ->
		emitter.on 'stdout', send = client.write.bind client
		emitter.on 'stderr', send
		client.on 'close', cleanup = ->
			emitter.removeListener 'stdout', send
			emitter.removeListener 'stderr', send
			try client.close()
		client.on 'disconnect', cleanup
		client.on 'error', cleanup
	setOutput: (url, tee=false, remove=false) ->
		url = $.URL.parse(url)
		p = url.protocol
		if remove
			s = $.URL.stringify(url)
			for i in $.range(0,drivers.length).filterMap((i) -> if drivers[i].url is s then i else null).reverse()
				drivers.splice i, 1
		else if d = drivers[p]
			driver = new drivers[p](url)
			if tee
				outputs.push driver
			else
				for driver in outputs
					driver.close?()
				outputs = [ driver ]
		else
			warn "No such output driver: "+p
	stdout: new Stream.Writable write: writeToAll 'stdout'
	stderr: new Stream.Writable write: writeToAll 'stderr'
}

Output.teeOutput('console://')
$.log.out = Output.echo
$.extend module.exports, Output
