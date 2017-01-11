#!/bin/bash

ROOT=`dirname $0`/..
source $ROOT/test/common.sh

echo '
{
	"servers": [ {
		"count": 1,
		"port": 9002,
		"cd": "test/server",
		"command": "node app.js crash-mode"
	}, {
		"count": 2,
		"port": 9003,
		"cd": "test/server",
		"command": "node app.js"
	} ],
	"admin": { "port": 9001 },
	"nginx": { "enabled": false },
	"rabbitmq": { "enabled": false }
}
' > $JSON_FILE
PORTS="9002 9003 9004"

# this test is not concerned with starting 'over the top'
# of an already running instance, so we kill it all first
kill_owner 9001
for PORT in $PORTS; do
	kill_owner $PORT
done

shepherd_start
sleep 18 # add extra sleep time to let the crashing finish
for PORT in $PORTS; do
	check_output $PORT
done
shepherd_stop
