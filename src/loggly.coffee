
# Goal: provide an output stream that wraps Loggly
module.exports.createWriteStream = (opts) ->
	client = require('loggly').createClient(opts)
	return {
		write: (data, enc) -> client.log(data)
	}

