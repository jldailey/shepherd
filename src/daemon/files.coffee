
Shell = require 'shelljs'
basePath = "#{process.env.HOME}/.shepherd"
Shell.exec("mkdir -p #{basePath}", { silent: true })
makePath = (parts...) -> [basePath].concat(parts).join "/"

module.exports = {
	pidFile: makePath "pid"
	socketFile: makePath "socket"
	configFile: makePath "config"
}
