$ = require 'bling'
stream = require 'stream'

drivers = {
	console: {
		createWriteStreams: -> [ process.stdout, process.stderr ]
	}
	file: {
		createWriteStreams: (url) ->
			stdout = Fs.createWriteStream(url.path)
			[stdout, stdout]
	}
	loggly: require('./driver-loggly')
	mongodb: require('./driver-mongodb')
}

emitter = $.EventEmitter()

# manually select and initialize the console output driver
currentDriver = drivers.console
[drivers.console.stdout, drivers.console.stderr] = drivers.console.createWriteStreams { protocol: "console" }

module.exports = Output = {
	echo: (args...) ->
		Output.stdout.write args.map($.toString).join(' ') + '\n'
	tail: (client) ->
		emitter.on 'stdout', send = client.write.bind client
		emitter.on 'stderr', send
		client.on 'close', cleanup = ->
			emitter.removeListener 'stdout', send
			emitter.removeListener 'stderr', send
			try client.close()
		client.on 'disconnect', cleanup
		client.on 'error', cleanup
	setOutput: (url) ->
		url = $.URL.parse(url)
		p = url.protocol
		if d = drivers[p]
			[d.stdout, d.stderr] = d.createWriteStreams url
			currentDriver = d
		else
			Output.echo "No such output driver: "+p
	stdout: new stream.Writable write: (data, enc, cb) ->
		emitter.emit 'stdout', data, enc
		currentDriver.stdout.write data, enc, cb
	stderr: new stream.Writable write: (data, enc, cb) ->
		emitter.emit 'stderr', data, enc
		currentDriver.stderr.write data, enc, cb
}

Output.setOutput('console://')
$.log.out = Output.echo
$.extend module.exports, Output
