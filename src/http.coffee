$         = require 'bling'
Express   = require 'express'
BasicAuth = require 'basic-auth'
Http      = require 'http'
Static    = require 'serve-static'
Helpers   = require './helpers'
Opts      = require './opts'
log       = $.logger '[http]'
app       = Express()

app.use (req, res, next) ->
	log req.method, req.url, "(-)"
	next()

# serve some static js files
app.use "/static", Static __dirname + '/../static', index: false

# default credentials
http_username = Opts.username ? "demo"
http_password = Opts.password ? "demo"

plain = (next) ->
	basicAuth http_username, http_password, (req, res) -> # a plain-text request handler (password-protected)
		res.contentType = "text/plain"
		res.send = (status, content, enc = "utf8") ->
			res.statusCode = status
			try res.end(content, enc)
			catch err
				res.statusCode = 500
				res.end(String(err), enc)
		res.pass = (content) ->
			res.send 200, switch $.type content
				when "string","buffer"        then content
				when "object","array","bling" then JSON.stringify content, null, "  "
				else $.toRepr content
		res.html = (content) ->
			res.writeHead 200, { "Content-Type": "text/html" }
			res.end String(content)
		res.fail = (err) ->
			res.send 500, switch $.type err
				when "error"                  then $.debugStack err
				when "string","buffer"        then err
				when "object","array","bling" then JSON.stringify err
				else $.toRepr content
		return next req, res

basicAuth = (user, pass, next) ->
	(req, res) ->
		credentials = BasicAuth(req)
		unless credentials? and credentials.name is user and credentials.pass is pass
			res.writeHead(401, {
				"WWW-Authenticate": 'Basic realm="shepherd"'
			})
			res.end()
		else next req, res

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
	close: ->
		try return p = $.Promise()
		finally
			try server.close (err) ->
				if err then p.reject err
				else p.resolve()
			catch _err then p.reject _err
}

for method in ["get", "put", "post", "delete"] then do (method) ->
	module.exports[method] = (path, handler) -> $.publish "http-route", method, path, handler
