{ warn } = require "./index"

trueFalse = (s) -> s in ['true','yes','on']

usage = ->
	warn "A loggly url should be specified like loggly://<subdomain>?token=<token>[&tags=a,b,c][&json=false]"

module.exports = class LogglyDriver
	constructor: (url, parsed) ->
		@url = url
		@supportsColor = false
		unless 'token' of parsed.query
			throw new Error "'token' is a required parameter for loggly."
		client = require('loggly').createClient({
			token: parsed.query.token
			subdomain: parsed.host
			tags: parsed.query.tags.split /, */
			json: trueFalse parsed.query.json
		})
		$.extend @,
			supportsColor: false
			stdout: stdout = new stream.Writable write: (data, enc, cb) ->
				client.log(data.toString(enc))
				cb()
			stderr: stdout
			close: -> client?.close?()
