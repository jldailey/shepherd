$ = require "bling"
RabbitJS = require 'rabbit.js'
Opts = require './opts'
log = $.logger "[rabbit]"
verbose = (a...) -> if Opts.verbose then log a...

ready = $.Promise()

property = (v) -> (n) -> v = n ? v

# note-taking for multiple subscriptions to the same channel
sockets = Object.create null
patterns = Object.create null

$.extend module.exports, Rabbit = {
	defaultChannel: property("shepherd")
	defaultUrl:     property("amqp://localhost:5672")
	connect:   (url = Rabbit.defaultUrl()) ->
		log "Connecting to...", url
		context = RabbitJS.createContext url
		context.on "ready", ->
			log "Connected."
			ready.resolve context
		context.on "error", (err) ->
			log "Failed to connect to",url,err
			ready.reject err
		return ready
	publish:   (m, c = Rabbit.defaultChannel()) ->
		try return p = $.Promise()
		finally ready.wait (err, context) ->
			pub = context.socket 'PUB'
			pub.connect c, ->
				pub.write JSON.stringify(m), 'utf8'
				pub.close()
				p.resolve()
	match: (p, h) -> Rabbit.subscribe Rabbit.defaultChannel(), p, h
	subscribe: (c, p, h) ->
		if $.is 'function', c
			h = c
			p = null
			c = Rabbit.defaultChannel()
		else if $.is 'function', p
			h = p
			p = null
		p ?= $.matches.Any
		ready.wait (err, context) ->
			verbose "adding route:", c, $.toRepr p
			if err? then return log "error:", err
			sub = sockets[c]
			args = { p, h }
			onData = null
			if sub? # we already have subscriptions to this channel
				patterns[c].push args
			else
				patterns[c] = [ args ]
				sockets[c] = sub = context.socket 'SUB'
				sub.on 'data', onData = (data) ->
					try data = JSON.parse data
					catch err then return log "JSON.parse error:", err.message, "in", data
					list = patterns[c]
					for args in list
						if $.matches args.p, data
							try args.h data
							catch err then log "error in handler:", err.stack
				sub.on 'drain', onData
				sub.connect c, ->
					verbose "subscribed to channel", c, p
}

if require.main is module
	Rabbit.connect().then ->
		Rabbit.defaultChannel("test-messages")
		Rabbit.subscribe (m) ->
			console.log "->:", m
		$.delay 100, ->
			Rabbit.publish({ some: "stuff" }).then ->
				$.delay 100, ->
					process.exit 0
