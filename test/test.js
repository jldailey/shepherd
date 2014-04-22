
// Features to test:
// start a flock
// kill a flock
// restart a flock (rolling)
// recieve signals via
//	http
//	amqp
//
// High-level:
// start a flock of processes
// check that they are all up (by reading server/totem and comparing to response totem)
// mv server/_git .git
// mv developer/_git .git
// cd developer
// echo random() > totem
// git commit totem -m "fake commit"
// git push
// trigger a git pull and rolling restart
// check that all the processes have the correct new totem
$ = require("bling")
Shell = require("shelljs")
Helpers = require("../lib/helpers")
Request = require('request')
log = $.logger("[test]")

fail = function(err) {
	log("Fatal:", err)
	cleanUp()
}

request = function(url, cb) {
	log("Request:", url)
	Request(url, function(error, response) {
		if( error != null ) return fail(err)
		cb(response.body)
	})
}

log("Preparing .git folders...")
$.Promise.exec("mv test/fixtures/server/_git test/fixtures/server/.git").wait(function() {
	$.Promise.exec("mv test/fixtures/developer/_git test/fixtures/developer/.git").wait(function() {

		// start a flock from test/fixtures/server
		var shepherd = Shell.exec("bin/shepherd -f test/herd", { async: true, silent: true }),
			data_out = function(data) {
				data.split(/\n/).forEach(function(d) { if( d.length ) log(d) })
			}, trigger = function(pattern, cb) {
				shepherd.stdout.on('data', function(data) {
					data.split(/\n/).forEach(function(d) {
						if(d.match(pattern)) cb(d)
					})
				})
			}

		shepherd.on('exit', function (exitCode) {
			log('shepherd.onExit', exitCode)
		})

		// wait for the master server to come online
		trigger(/listening on master port/i, function(line) {
			// check that all 4 children started
			request("http://localhost:8000/", log)
			request("http://localhost:8001/", log)
			request("http://localhost:8002/", log)
			request("http://localhost:8003/", log)
			// cause a 'git pull' and rolling restart
			request("http://localhost:9000/children/update", log)
			// wait for the last child to have started
			trigger(/Listening on port 8003/, function() {
				var done = $.Progress(4),
					step = function(body) {
						log(body); done.finish(1)
					}
				// check all 4 children again
				request("http://localhost:8000/", step)
				request("http://localhost:8001/", step)
				request("http://localhost:8002/", step)
				request("http://localhost:8003/", step)
				// Success!
				done.then(function() {
					log("Tests complete.")
					cleanUp()
				})
			})
		})

		shepherd.stdout.on('data', data_out)
		shepherd.stdout.on('drain', data_out)
		shepherd.stderr.on('data', data_out)
		shepherd.stderr.on('drain', data_out)
		shepherd.on('error', log)

	})
})

function cleanUp() {
	log("Cleaning up .git folders...")
	$.Promise.exec("mv test/fixtures/server/.git test/fixtures/server/_git").wait(function() {
		$.Promise.exec("mv test/fixtures/developer/.git test/fixtures/developer/_git").wait(function() {
			log("Exiting gracefully...")
			process.exit(0)
		})
	})
}

['exit', 'SIGINT', 'SIGTERM'].map(function(signal) {
	process.on(signal, cleanUp)
})

