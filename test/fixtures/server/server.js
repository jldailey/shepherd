Http = require('http')

console.log("Listening on port", process.env.PORT)

Http.createServer(function(req, res) {
	res.statusCode = 200;
	res.end("OK: " + String(process.env.PORT));
	console.log(req.method + " " + req.path + " " + res.statusCode)
}).listen(process.env.PORT);
