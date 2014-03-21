
Shepherd
--------

Process launching, monitoring, and continuous integration.

Goals:

* Start N processes, each on their own port.
* Load configuration from a .env file.
* Restart all processes, one at a time.
* Listen for github webhook messages with an http server.
	* After a "push" event or a "release" event,
	* Pull new code from git, followed by a rolling restart.

