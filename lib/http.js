(function() {

	var $ = require('bling'),
		Express = require('express'),
		Http = require('http'),
		Git = require('./git'),
		toBr = function(s) { return String(s)
			.replace(/(?:\n|\r)/g,"<br>")
			.replace(/\t/g,"    ")
		},
		log = $.logger("[http]"),
		app = Express()

	app.get("/", function(req, res) {
		res.statusCode = 200;
		res.end("Welcome to the Shepherd.")
	})

	// allow other modules to inject routes by publishing them locally
	$.subscribe('http-route', function(method, path, handler) {
		method = method.toLowerCase()
		log("adding published route:", method, path)
		app[method].call(app, path, handler)
	})

	server = Http.createServer(app)

	$.extend(module.exports, {
		toBr: toBr, // a helpful utility
		listen: function(port) {
			server.listen(port, function(err) {
				if( err != null ) log("failed to listen on port:",port,"error:",err)
				else log("listening on master port:", port)
			})
		}
	})

})(this)
