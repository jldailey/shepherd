
Shepherd
--------

Process launching, monitoring, and continuous integration.

Install:
`npm install <shepherd-git-repo>`


Usage:
`shepherd [options]`

    -h, --help     output usage information
    -V, --version  output the version number
    -f [file]      The herd file to load
    -o [file]      Where to send log output.
    Note: output to stdout is synchronous (blocking).
    --defaults     Output a complete herd file with all defaults
    --daemon       Run in the background.
    --verbose      Verbose mode.
    -p [file]      The .pid file to use.
    
Sample herd file:

    { "exec":
      { "cd": ".",
        "cmd": "node index.js",
        "count": 3,
        "port": 8000,
        "portVariable": "PORT"
        "env": {}
      },
      "restart":
      { "maxAttempts": 5,
        "maxInterval": 10000,
        "gracePeriod": 3000,
        "timeout": 10000
      },
      "git":
      { "remote": "origin",
        "branch": "master",
        "command": "git pull {{remote}} {{branch}} || git merge --abort"
      },
      "rabbitmq": { "url": "amqp://localhost:5672", "exchange": "shepherd" },
      "nginx":
      { "config": "/usr/local/etc/nginx/conf.d/shepherd_pool.conf",
        "reload": "launchctl stop homebrew.mxcl.nginx && launchctl start homebrew.mxcl.nginx"
      },
      "admin": { "port": 9000 }
    }
