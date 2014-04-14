Http = require('http')

setTimeout(function() {
	Http.createServer(function(req, res) {
		res.statusCode = 200;
		res.end("OK: " + String(process.env.PORT));
		console.log(req.method + " " + req.url + " " + res.statusCode)
	}).listen(process.env.PORT);
	console.log("Listening on port", process.env.PORT)
}, 2000) // add an artificial startup delay
