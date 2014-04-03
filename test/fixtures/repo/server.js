require 'http'

http.createServer(function(req, res) {
	res.statusCode = 200;
	res.end("OK");
}).listen(process.env.PORT);
