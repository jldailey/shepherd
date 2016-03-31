
trueFalse = (s) -> s in ['true','yes','on']

usage = ->
	console.error "Error: a loggly url must be specified like loggly://<subdomain>?token=<token>[&tags=a,b,c][&json=false]"

module.exports = class LogglyDriver
	constructor: (url) ->
		@url = $.URL.stringify url
		@supportsColor = false
		unless 'token' of url.query
			throw new Error "'token' is a required parameter for loggly."
		client = require('loggly').createClient({
			token: url.query.token
			subdomain: url.host
			tags: url.query.tags.split /, */
			json: trueFalse url.query.json
		})
		$.extend @,
			supportsColor: false
			stdout: stdout = new stream.Writable write: (data, enc, cb) ->
				client.log(data.toString(enc))
				cb()
			stderr: stdout
			close: -> client?.close?()
