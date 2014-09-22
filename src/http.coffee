$ = require('bling'),
Express = require('express'),
Http = require('http'),
Helpers = require('./helpers'),
Opts = require("./opts"),
log = $.logger("[http]"),
app = Express()

app.get "/", (req, res) ->
	Helpers.jsonFile("../package.json").then (pkg) ->
		res.contentType = "text/html"
		res.send 200, """<html>"
			<head></head><body>
			Welcome to <b>Shepherd</b> version #{pkg.version}<br>"
			</body>
		"""

# allow other modules to inject routes by publishing them
$.subscribe 'http-route', (method, path, handler) ->
	method = method.toLowerCase()
	if Opts.verbose then log("adding published route:", method, path)
	app[method].call(app, path, handler)

server = Http.createServer app

$.extend module.exports, {
	listen: (port) ->
		try return p = $.Promise()
		finally server.listen port, (err) ->
			if err then p.reject err
			else p.resolve port
}
