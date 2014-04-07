Http = require('http')

console.log("Listening on port", process.env.PORT)

Http.createServer(function(req, res) {
	res.statusCode = 200;
	res.end("OK");
}).listen(process.env.PORT);
