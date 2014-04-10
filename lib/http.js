(function() {

	var Express = require('express'),
		Http = require('http'),
		Git = require('./git'),
		toBr = function(s) { return s.replace("\n", "<br>")
			.replace("\r","<br>")
			.replace("\t","    ")
		},
		log = $.logger("[http]"),
		app = Express()
			.use(Express.logger())

		app.get("/", function(req, res) {
			res.statusCode = 200;
			res.end("Hi")
		})

		// allow other modules to inject routes by publishing them locally
		$.subscribe('http-route', function(method, path, handler) {
			method = method.toLowerCase()
			log("adding published route:", method, path)
			app[method].call(app, path, handler)
		})

		module.exports = Http.createServer(app)
	
})(this)
