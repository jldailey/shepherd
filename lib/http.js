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

		app.get("/git/status", function(req, res) {
			res.statusCode = 200;
			Git.status().wait(function (err, output) {
				if (err != null) {
					res.end(err.toString())
				} else {
					res.end(toBr(output))
				}
			})
		})

		app.get("/git/pull", function(req, res) {
			res.statusCode = 200
			origin = req.params['origin'] || "origin"
			branch = req.params['branch'] || "master"
			html = "git pull " + origin + " " + branch + "<br>";
			Git.pull(origin, branch).wait(function (err, output) {
				html += "git pull " + origin + " " + branch + " : "
					+ err.toString() + "output: "
					+ toBr(output)
				if (err != null) {
					Git.mergeAbort().wait(function (err, output) {
						html += "git merge --abort: "
						if( err != null) {
							html += err.toString()
						}
						html += " output: " + toBr(output)
					})
				}
			})
			res.end(html)
		})

		// allow other modules to inject routes by publishing them locally
		$.subscribe('http-route', function(method, path, handler) {
			method = method.toLowerCase()
			$.log("adding published route", method, path, handler)
			app[method].call(app, path, handler)
		})

		module.exports = Http.createServer(app)
	
})(this)
