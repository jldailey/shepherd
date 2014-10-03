$       = require 'bling'
Express = require 'express'
Http    = require 'http'
Helpers = require './helpers'
Opts    = require "./opts"
log     = $.logger "[http]"
app     = Express()
http_username = Opts.username ? "demo"
http_password = Opts.password ? "demo"

plain = (next) ->
	basicAuth http_username, http_password, (req, res) -> # a plain-text request handler (password-protected)
		res.contentType = "text/plain"
		res.send = (status, content, enc = "utf8") ->
			res.statusCode = status
			res.end(content, enc)
		res.pass = (content) -> res.send 200, content
		res.fail = (err) ->
			if err?.stack then res.send 500, err.stack
			else if $.is 'string', err then res.send 500, err
			else res.send 500, JSON.stringify err
		return next req, res

basicAuth = (user, pass, next) ->
	(req, res) ->
		credentials = BasicAuth(req)
		unless credentials? and credentials.name is user and credentials.pass is pass
			res.writeHead(401, {
				"WWW-Authenticate": 'Basic realm="shepherd"'
			})
			res.end()
		return next req, res

# allow other modules to inject routes by publishing them
$.subscribe 'http-route', (method, path, handler) ->
	method = method.toLowerCase()
	if Opts.verbose then log("adding published route:", method, path)
	app[method].call(app, path, plain handler)

server = Http.createServer app

$.extend module.exports, {
	listen: (port) ->
		try return p = $.Promise()
		finally
			try server.listen port, (err) -> if err then p.reject err else p.resolve port
			catch _err then p.reject _err
}

for method in ["get", "put", "post", "delete"] then do (method) ->
	module.exports[method] = (path, handler) -> $.publish "http-route", method, path, handler
