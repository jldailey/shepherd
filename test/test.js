
Shell = require("shelljs")

describe("shepherd", function() {

	beforeEach(function() {
		Shell.exec("mv fixtures/repo/_git fixtures/repo/.git", function() {
			Shell.exec("mv fixtures/server/_git fixtures/server/.git", function() {
			})
		})
	})

	afterEach(function() {
		Shell.exec("mv fixtures/repo/.git fixtures/repo/_git", function() {
			Shell.exec("mv fixtures/server/.git fixtures/server/_git", function() {
			})
		})
	})

})
