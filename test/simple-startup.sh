#!/bin/bash

ROOT=`dirname $0`/..
TEST_NAME=`basename $0 | sed s/\.sh//`
source $ROOT/test/common.sh

PORTS="8001 8002 8003"

echo '
{
	"servers": [ {
		"count": 3,
		"port": 8001,
		"cd": "test/server",
		"command": "node app.js"
	} ],
	"admin": { "port": 9001 },
	"nginx": { "enabled": false },
	"rabbitmq": { "enabled": false }
}
' > $JSON_FILE

echo > $LOG_FILE
# this test is not concerned with starting 'over the top'
# of an already running instance, so we kill it all first
kill_owner 9001
for PORT in $PORTS; do
	kill_owner $PORT
done

shepherd_start
for PORT in $PORTS; do
	check_output $PORT "{\"PORT\": $PORT, \"TOKEN\": \"123456\"}" 
done
shepherd_stop
