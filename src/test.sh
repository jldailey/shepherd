#!/bin/sh

coffee src/daemon.coffee stop && coffee src/daemon.coffee start &
sleep 1
coffee src/opts.coffee add --group api --cd test/server --exec 'node app.js' -n 4 --port 8000
coffee src/opts.coffee start --instance api-1
sleep 1
coffee src/opts.coffee status

