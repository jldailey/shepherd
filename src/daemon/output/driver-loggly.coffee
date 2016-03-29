	if config.loggly?.enabled
		outputs['loggly'] = require("./loggly").createWriteStream {
			token: config.loggly.token
			subdomain: config.loggly.subdomain
			tags: config.loggly.tags ? []
			json: config.loggly.json ? false
		}
		verbose "Opened output stream to Loggly (#{config.loggly.subdomain})."

trueFalse = (s) -> s in ['true','yes','on']

module.exports.createWriteStream = (url) ->
	unless 'subdomain' of url.query
		throw new Error "'subdomain' is a required parameter for loggly."
	unless 'token' of url.query
		throw new Error "'token' is a required parameter for loggly."
	client = require('loggly').createClient({
		token: url.query.token
		subdomain: url.query.subdomain
		tags: url.query.tags.split /, */
		json: trueFalse url.query.json
	})

	return new stream.Writable write: (data, enc, cb) ->
		client.log(data.toString(enc))
		cb()
