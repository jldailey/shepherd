var Shell = require('shelljs'),
	$ = require('bling'),
	Worker = module.exports = function Worker(herd, index) {
		this.herd = herd;
		this.index = index || 0;
		this.process = null;
		this.startAttempts = 0;
		this.maxAttempts = 3;
		this.maxInterval = 3000;
		this.startReset = null;
		this.started = $.Promise();
		this.log = $.logger("worker[" + this.index + "]")
		Worker.count += 1;
	}

Worker.count = 0;

Worker.prototype.spawn = function() {
	var self = this,
		cmd = "bash -c 'cd " + self.herd.cd + " && " + self.herd.cmd + "'"
	self.started.reset()
	self.process = Shell.exec(cmd, { silent: true, async: true }, $.identity)
	self.process.on("exit", function(err, code) { self.onExit(code) })
	self.process.stdout.on("data", function(data){
		$(data.split(/\n/)).each(function(line) {
			if( line.length > 0 )
				self.log(line)
		})
	})
	self.process.stderr.on("data", function(data){
		$(data.split(/\n/)).each(function(line) {
			if( line.length > 0 )
				self.log("(stderr)", line)
		})
	})
	self.started.resolve(self.process.pid)
	return self.started;
}

Worker.prototype.kill = function(signal) {
	var self = this,
		p = $.Promise()
	if( self.process == null ) return p.reject('no process')
	self.process.on('exit', function(exitCode) {
		p.resolve(exitCode)
	})
	self.process.kill(signal)
	return p
}

Worker.prototype.onExit = function(exitCode) {
	var self = this;
	if( self.process == null ) {
		return;
	}
	Worker.count -= 1
	self.log("Worker PID: " + self.process.pid + " exited with code: ", exitCode);
	// Record the death of the child
	self.process = null;
	// if it died with a restartable exit code, attempt to restart it
	if ( exitCode != "SIGKILL" && self.startAttempts < self.maxAttempts ) {
		self.startAttempts += 1;
		// schedule the forgetting of start attempts
		clearTimeout(self.startReset);
		self.startReset = setTimeout( function() {
			self.startAttempts = 0;
		}, self.maxInterval)
		// attempt a restart
		self.spawn();
	}
}
