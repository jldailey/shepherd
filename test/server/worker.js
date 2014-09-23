function tick() {
	console.log("worker:", process.pid, "working at", new Date())
	setTimeout(tick, 3000);
}

tick()

process.on('exit', function(err, signal) {
	console.log("worker:", process.pid, "exit", err, signal)
})

