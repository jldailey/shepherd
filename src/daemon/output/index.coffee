$ = require 'bling'

drivers = {
	console: {
		init: ->
		stdout: process.stdout
		stderr: process.stderr
	}
	file: {
		init: (url) ->
			console.log "Opening file for output #{url.path}", url
			drivers.file.stderr = \
				drivers.file.stdout = \
				Fs.createWriteStream(url.path)
	}
	loggly: require('./driver-loggly')
	mongodb: require('./driver-mongodb')
}

currentDriver = 'console'
module.exports = {
	echo: (args...) ->
		module.exports.stdout.write args.map($.toString).join(' ') + '\n'
	setOutput: (url) ->
		url = $.URL.parse(url)
		p = url.proto
		if p of drivers
			drivers[p].init url
			currentDriver = p
}
$.defineProperty module.exports, 'stdout', get: -> drivers[currentDriver].stdout
$.defineProperty module.exports, 'stderr', get: -> drivers[currentDriver].stderr

