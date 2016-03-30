
unless 'HOME' of process.env
	"No $HOME in environment, can't place .shepherd directory."
	process.exit 1

Shell = require 'shelljs'

basePath = "#{process.env.HOME}/.shepherd"
Shell.exec("mkdir -p #{basePath}", { silent: true })
makePath = (parts...) -> [basePath].concat(parts).join "/"
module.exports = {
	pidFile: makePath "pid"
	socketFile: makePath "socket"
	configFile: makePath "config"
}
