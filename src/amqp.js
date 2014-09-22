var $ = require("bling"),
	Rabbit = require('rabbit.js'),
	Opts = require('./opts'),
	log = $.logger("[amqp]")

$.extend(module.exports, {
	connect: function(url) {
		log("Connecting to...", url)
		var ready = $.Promise(),
			sockets = {},
			patterns = {},
			context = Rabbit.createContext(url)
		context.on("ready", function() {
			log("Connected.")
			ready.resolve(context)
		})
		context.on("error", function(err) {
			log("Failed to connect to",url,err)
			ready.reject(err)
		})
		// use a local subscription to register message handlers from within any other module
		$.subscribe("amqp-route", function(channel, pattern, handler) {
			ready.wait(function(err, context) {
				if( Opts.verbose ) log("adding route:", channel, $.toRepr(pattern))
				if( err != null ) {
					return log("error:", err)
				}
				var i, list,
					sub = sockets[channel],
					obj = { pattern: pattern, handler: handler },
					onData = null

				if( sub != null ) { // we already have subscriptions to this channel
					patterns[channel].push(obj)
				} else {
					patterns[channel] = [ obj ]
					sockets[channel] = sub = context.socket('SUB')
					sub.on('data', onData = function (data) {
						// TODO: when sending really large json blobs, they may not all fit in one 'data' call
						// manual buffering may be required.
						try {
							data = JSON.parse(String(data));
						} catch( err ) {
							return log("JSON.parse error:", err.message, "in", String(data))
						}
						list = patterns[channel]
						for( i = 0; i < list.length; i++ ) {
							if( $.matches(list[i].pattern, data) ) {
								try {
									list[i].handler(data)
								} catch(err) {
									log("error in handler:", err.stack)
									// continue with other handlers
								}
							}
						}
					})
					sub.on('drain', onData)
					sub.connect(channel, function() {
						log("connected to channel", channel)
					})
				}
			})
		})
		return ready
	}
})
