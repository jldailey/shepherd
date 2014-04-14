
$ = require("bling")
Shell = require("shelljs")

log = $.logger("[test]")

shepherd = Shell.exec("bin/shepherd -f test/herd", { silent: true, async: true }, function(exitCode) {
	log("shepherd exitCode:", exitCode)
})

shepherd.stdout.on('data', function(data) {
	log(data)
})

shepherd.stderr.on('data', function(data) {
	log("[stderr]", data)
})

shepherd.on("exit", function() {
	log("Test complete.")
})
