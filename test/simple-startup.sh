#!/bin/bash

source `dirname $0`/common.sh

JSON_FILE=/tmp/simple-startup.json

echo '
{
	"servers": [ {
		"count": 2,
		"port": 8001,
		"cd": "test/server",
		"command": "node app.js",
		"poolName": "shepherd_pool"
	} ],
	"admin": { "port": 9001 },
	"nginx": { "enabled": false },
	"rabbitmq": { "enabled": false }
}
' > $JSON_FILE

# this test is not concerned with starting 'over the top'
# of an already running instance, so we kill it all
kill_owner 9001
kill_owner 8001
kill_owner 8002

./bin/shepherd -v -f $JSON_FILE
rm $JSON_FILE
