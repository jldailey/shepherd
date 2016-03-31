
trueFalse = (s) -> s in ['true','yes','on']

usage = ->
	console.error "Error: a loggly url must be specified like loggly://<subdomain>?token=<token>[&tags=a,b,c][&json=false]"

module.exports.createWriteStreams = (url) ->
	unless 'token' of url.query
		throw new Error "'token' is a required parameter for loggly."
	client = require('loggly').createClient({
		token: url.query.token
		subdomain: url.host
		tags: url.query.tags.split /, */
		json: trueFalse url.query.json
	})

	stdout = new stream.Writable write: (data, enc, cb) ->
		client.log(data.toString(enc))
		cb()
	
	return [stdout, stdout]
