$ = require "bling"
Rabbit = require 'rabbit.js'
Opts = require './opts'
log = $.logger "[rabbit]"

$.extend module.exports, {
	connect: (url) ->
		log "Connecting to...", url
		ready = $.Promise()
		sockets = Object.create null
		patterns = Object.create null
		context = Rabbit.createContext url
		context.on "ready", ->
			log "Connected."
			ready.resolve context
		context.on "error", (err) ->
			log "Failed to connect to",url,err
			ready.reject err
		# use a local subscription to register message handlers from within any other module
		$.subscribe "amqp-route", (channel, pattern, handler) ->
			ready.wait (err, context) ->
				if Opts.verbose then log "adding route:", channel, $.toRepr pattern
				if err? then return log "error:", err
				sub = sockets[channel]
				obj = { pattern, handler }
				onData = null
				if sub? # we already have subscriptions to this channel
					patterns[channel].push obj
				else
					patterns[channel] = [ obj ]
					sockets[channel] = sub = context.socket 'SUB'
					sub.on 'data', onData = (data) ->
						try data = JSON.parse String data
						catch err then return log "JSON.parse error:", err.message, "in", String data
						list = patterns[channel]
						for obj in list when $.matches obj.pattern, data
							try obj.handler data
							catch err then log "error in handler:", err.stack
					sub.on 'drain', onData
					sub.connect channel, -> log "connected to channel", channel
		return ready
}
