$ = require('bling')
require('./helpers')

$.extend(module.exports, {
	status: function() {
		return $.Promise.exec("git status")
	},
	pull: function(remote, branch) {
		return $.Promise.exec("git pull " + remote + " " + branch)
	},
	mergeAbort: function() {
		return $.Promise.exec("git merge --abort")
	}
})
