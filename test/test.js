
Shell = require("shelljs")

child = Shell.exec("../bin/shepherd -f .herd")


describe("shepherd", function(done) {
	var child = Shell.exec("../bin/shepherd -f ./fixtures/.herd", function(exitCode) {
		done();
	})
})
		
