
$ = require("bling")
Shell = require("shelljs")

describe("shepherd", function() {

	beforeEach(function(done) {
		Shell.exec("mv test/fixtures/repo/_git test/fixtures/repo/.git", function(exitCode) {
			Shell.exec("mv test/fixtures/server/_git test/fixtures/server/.git", function(exitCode) {
				done();
			})
		})
	})

	it("runs in a cwd", function(done) {
		Shell.exec("ls -l", { silent: true, async: true }, function(exitCode) {
			done();
		})
	})

	it("starts children", function(done) {
		shepherd = Shell.exec("bin/shepherd -f test/.herd", { silent: true, async: true }, function(exitCode) {
			$.log("shepherd exitCode:", exitCode)
			done();
		})
		shepherd.stdout.on('data', function(data) {
			$.log(data)
		})
		shepherd.stderr.on('data', function(data) {
			$.log("stderr", data)
		})
	})

	afterEach(function(done) {
		Shell.exec("mv test/fixtures/repo/.git test/fixtures/repo/_git", function(exitCode) {
			Shell.exec("mv test/fixtures/server/.git test/fixtures/server/_git", function(exitCode) {
				done();
			})
		})
	})

})
