Http = require('http')
Shell = require('shelljs')
Fs = require('fs')
$ = require('bling')

setTimeout(function() {
	Http.createServer(function(req, res) {
		var fail = function(err) {
			res.statusCode = 500;
			res.contentType = "text/plain";
			res.end(JSON.stringify(err))
		}, finish = function(html) {
			res.statusCode = 200;
			res.contentType = "text/html";
			res.end(html || "")
			console.log(req.method + " " + req.url + " " + res.statusCode)
		}, write = function(html) {
			res.write(html, 'utf8')
		}
		res.statusCode = 200;
		res.contentType = "application/json"
		write('{"PORT": ' + process.env.PORT + ', "TOTEM": "')
		Fs.readFile("totem", function(err, data) {
			if( err != null ) return fail(err)
			else finish(data + '"}')
		})
	}).listen(process.env.PORT);
	console.log("Listening on port", process.env.PORT)
}, 1000) // add an artificial startup delay
