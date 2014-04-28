var $ = require("bling"),
	Rabbit = require('rabbit.js'),

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
			ready.finish(context)
		})
		context.on("error", function(err) {
			log("Failed to connect to",url,err)
			ready.fail(err)
		})
		$.subscribe("amqp-route", function(channel, pattern, handler) {
			ready.wait(function(err, context) {
				log("adding published route:", channel, pattern)
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
						$.log("onData", String(data))
						try {
							data = JSON.parse(String(data));
							list = patterns[channel]
							for( i = 0; i < list.length; i++ ) {
								if( $.matches(list[i].pattern, data) ) {
									list[i].handler(data)
								}
							}
						} catch (err) {
							log("error:", err, err.stack)
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
