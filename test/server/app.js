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

function crashMode() {
	console.log("Crashing due to CRASH MODE!");
	$.delay(100, function() {
		process.exit(1);
	})
}

if( $(process.argv).contains('crash-mode') ) {
	var crashCount = 10, crashFile = '/tmp/crash-mode';
	try { crashCount = parseInt(String(Fs.readFileSync(crashFile)), 10); } catch(err) { }
	crashCount = Math.max(0, crashCount - 1)
	if( crashCount == 0 ) crashCount = 10;
	Fs.writeFileSync(crashFile, String(crashCount));
	if( crashCount < 10 ) crashMode();
}

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
				switch( requestCount % 5 ) {
					case 0:
					case 1:
					case 2: // fall through
					case 3: finish("IM OK"); break;
					case 4: $.random.element([function(){fail("NOT OK")}, function(){ console.log("TIMING OUT") }])()
				}
				break;
			default:
				finish('{"PORT": ' + process.env.PORT + ', "PID": "' + process.pid + '"}')
		}
	}).listen(process.env.PORT);
	console.log("Listening on port", process.env.PORT)
})
