$ = require 'bling'

module.exports = convert = (n) ->
	try return obj = {
		seconds: {
			to: {
				ms:      -> n * 1000
				minutes: -> n / 60
				hours:   -> n / 3600
			}
		},
		ms: {
			to: {
				seconds: -> n / 1000
				minutes: -> n / 60000
				hours:   -> n / 3600000
			}
		}
		minutes: {
			to: {
				ms:      -> n * 60000
				seconds: -> n * 60
				hours:   -> n / 60
			}
		}
		hours: {
			to: {
				minutes: -> n * 60
				seconds: -> n * 3600
				ms:      -> n * 3600000
			}
		}
	}
	finally for k, o of obj then for j, f of o.to
		$.defineProperty o.to, j, get: f
