Http = require('http');
Shell = require('shelljs');
Fs = require('fs');
$ = require('bling');
console.log("Test Server starting on PID:", process.pid);
["SIGHUP", "SIGINT", "SIGTERM"].forEach(function(signal) {
	process.on(signal, function() {
		console.log("got signal: " + signal);
		process.exit(0)
	})
});

requestCount = 0

$.delay(500, function() { // add an artificial startup delay
	Http.createServer(function(req, res) {
		var fail = function(err) {
			res.statusCode = 500;
			res.contentType = "text/plain";
			res.end(err.stack || err)
			console.log(req.method + " " + req.url + " " + res.statusCode)
		}, finish = function(text) {
			res.statusCode = 200;
			res.contentType = "text/plain";
			res.end(text || "")
			console.log(req.method + " " + req.url + " " + res.statusCode)
		}
		requestCount += 1;
		switch(req.url) {
			case "/health-check":
				switch( requestCount % 6 ) {
					// answer 4 OK in a row, then a NOT OK, then a timeout
					case 0: return; // timeout
					case 1:
					case 2:
					case 3: // fall through
					case 4: finish("IM OK"); break;
					case 5: fail("NOT OK"); break;
				}
				break;
			default:
				finish('{"PORT": ' + process.env.PORT + ', "PID": "' + process.pid + '"}')
		}
	}).listen(process.env.PORT);
	console.log("Listening on port", process.env.PORT)
})
