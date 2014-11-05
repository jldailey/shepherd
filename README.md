
The Shepherd
--------

Install:
`npm install the-shepherd`


Usage:
`shepherd [options]`

    -h, --help     output usage information
    -V, --version  output the version number
    -f [file]      The herd file to load
    -o [file]      Where to send log output.
    Note: output to a tty is synchronous (blocking).
    --example      Output a complete herd file with all defaults
    --daemon       Run in the background.
    -v, --verbose  Verbose mode.
    -p [file]      The .pid file to use.
    
Sample herd file:

    {
      admin: {port: 9000 }
			servers: [
				{ cd: ".",
					command: "node index.js",
					count: 3,
					port: 8000,
					portVariable: "PORT"
					env: {}
				}
      ],
      workers: [
				{ cd: "workers",
					command: "node worker.js"
					count: 2
				}
			],
      restart: {
				maxAttempts: 5,
        maxInterval: 10000,
        gracePeriod: 3000,
        timeout: 10000
      },
      rabbitmq: {
				enabled: true
				url: "amqp://guest:guest@localhost:5672",
				channel: "shepherd"
			},
      nginx: {
				enabled: true
				config: "/usr/local/etc/nginx/conf.d/shepherd_pool.conf",
        reload: "launchctl stop homebrew.mxcl.nginx && launchctl start homebrew.mxcl.nginx"
      }
    }
