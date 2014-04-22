var Shell = require('shelljs'),
	$ = require('bling'),
	Child = module.exports = function Child(herd, index) {
		this.herd = herd;
		this.index = index || 0;
		this.port = herd.port + index;
		this.process = null;
		this.startAttempts = 0;
		this.startReset = null;
		this.started = $.Promise();
		this.log = $.logger("child[:"+this.port+"]")
		Child.count += 1;
	}

Child.count = 0;

Child.prototype.spawn = function() {
	var self = this,
		env_string = self.makeEnvString()
		cmd = ""
	self.started.reset()
	self.log("Checking previous owner of", self.port)
	$.Promise.portOwner(self.port).wait(function(err, owner) {
		// if the port is being listened on
		if( owner != null && isFinite(owner) ) {
			self.log("Killing previous owner of", self.port, "PID:", owner)
			// kill the other listener (probably it's an old version of ourself)
			process.kill(owner)
			// give it a grace period to release the port before we try to re-spawn
			$.delay(self.herd.restart.gracePeriod, function() {
				self.spawn()
			})
			return self.started;
		}
		cmd = env_string + "bash -c 'cd " + self.herd.exec.cd + " && " + self.herd.exec.cmd + "'"
		log("Command:", cmd)
		self.process = Shell.exec(cmd, { silent: true, async: true }, $.identity)
		self.process.on("exit", function(err, code) { self.onExit(code) })
		self.process.stdout.on("data", function(data){
			data = data.replace(/\n/,'')
			self.log(data);
		})
		self.process.stderr.on("data", function(data){
			data = data.replace(/\n/g,'')
			self.log("(stderr)", data)
		})
		$.Promise.portIsOwned(self.process.pid, self.port, self.herd.restart.timeout).wait(function(err, owner) {
			if( err != null) return self.started.fail(err)
			else {
				self.serverPid = owner
				self.started.finish(owner)
			}
		})
	})
	return self.started;
}

Child.prototype.kill = function(signal) {
	var self = this,
		p = $.Promise()
	if( self.process == null ) return p.fail('no process')
	self.process.on('exit', function(exitCode) {
		p.finish(exitCode)
	})
	self.process.kill(signal)
	return p
}

Child.prototype.onExit = function(exitCode) {
	var self = this;
	if( self.process == null ) {
		return;
	}
	Child.count -= 1
	self.log("Child PID: " + self.process.pid + " Exited with code: ", exitCode);
	// Record the death of the child
	self.process = null;
	// if it died with a restartable exit code, attempt to restart it
	if ( exitCode != "SIGKILL" && self.startAttempts < self.herd.restart.maxAttempts ) {
		self.startAttempts += 1;
		// schedule the forgetting of start attempts
		clearTimeout(self.startReset);
		self.startReset = setTimeout( function() {
			self.startAttempts = 0;
		}, self.herd.restart.maxInterval)
		// attempt a restart
		self.spawn();
	}
}

Child.prototype.toString = function() {
	return "[P:"+this.port+"]"
}

Child.prototype.getResources = function() {
	var self = this,
		cmd = "ps auxww | grep '\\<"+self.serverPid+"\\>' | grep -v grep | awk '{print \$3, \$4}'"
	return $.Promise.exec(cmd)
}

Child.prototype.makeEnvString = function() {
	var self = this,
		key, val,
		ret = "";
	for( key in self.herd.env ) {
		val = self.herd.env[key]
		if( val == null ) continue;
		ret += key + '="'+val+'" '
	}
	ret += self.herd.portVariable + '="'+self.port+'" '
	return ret
}
