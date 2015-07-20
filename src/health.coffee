$ = require 'bling'
http = require 'http'
Opts = require './opts'
Process = require './process'
log = $.logger "[monitor]"
verbose = (a...) -> if Opts.verbose then log a...

# keep a mapping from port to interval (i.e. setInterval) of the monitor
monitors = Object.create(null)

int = (n) -> parseInt n, 10

monitor = (port, pid, check) ->
	if port of monitors
		verbose "IGNORED: attempt to monitor the same port twice (port: #{port})"
		return
	# 'check' is the opts.check block from the servers section of the shepherd.json file
	# example:
	# "enabled": true
	# "url": "/health-check"
	# "status": 200
	# "contains": "IM OK"
	# "timeout": 1000
	# "interval": 5000
	return unless check.enabled
	log "Starting health checks for pid:", pid, "port:", port
	check.interval = int check.interval
	check.status   = int check.status
	check.timeout  = int check.timeout
	try check.contains = new RegExp check.contains
	fail = (err) -> (_err) ->
		if port of monitors
			log "Health check failed (port=#{port} pid=#{pid}), due to", err, "caused by", _err
			unmonitor(port)
			Process.killTree(pid, 15)

	monitors[port] = $.interval check.interval, ->
		req = http.request {
			port: port
			path: check.url
		}, (res) ->
			unless res.statusCode is check.status
				return do fail("bad status: #{res.statusCode}")
			res.setEncoding 'utf8'
			if check.contains?
				buffer = ""
				res.on 'data', (chunk) -> buffer += chunk
				res.on 'end', ->
					unless check.contains.test buffer
						do fail("response body does match regex: #{check.contains.toString()}")
				res.on 'error', fail('response error')
		req.setTimeout check.timeout
		req.on 'timeout', fail('timeout')
		req.on 'error', fail('request error')
		req.end()

unmonitor = (port) ->
	return unless port of monitors
	monitors[port].cancel()
	delete monitors[port]

$.extend module.exports, { monitor, unmonitor }
