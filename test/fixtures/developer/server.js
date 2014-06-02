Http = require('http')
Shell = require('shelljs')
Fs = require('fs')
$ = require('bling')

setTimeout(function() {
	Http.createServer(function(req, res) {
		var fail = function(err) {
			res.statusCode = 500;
			res.contentType = "text/plain";
			res.end(err.stack)
			console.log(req.method + " " + req.url + " " + res.statusCode)
		}, finish = function(text) {
			res.statusCode = 200;
			res.contentType = "text/plain";
			res.end(html || "")
			console.log(req.method + " " + req.url + " " + res.statusCode)
		}
		Fs.readFile("token", function(err, data) {
			if( err != null ) fail(err)
			else finish('{"PORT": ' + process.env.PORT + ', "TOKEN": "' + String(data).replace(/(?:\n|\r)/g,'') + '"}')
		})
	}).listen(process.env.PORT);
	console.log("Listening on port", process.env.PORT)
}, 500) // add an artificial startup delay
