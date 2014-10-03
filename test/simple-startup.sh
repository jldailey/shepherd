#!/bin/bash

ROOT=`dirname $0`/..
source "$ROOT/test/common.sh"

JSON_FILE=/tmp/simple-startup.json
PID_FILE=/tmp/simple-startup.pid
LOG_FILE=/tmp/simple-startup.log
PORTS="8001 8002 8003"

echo '
{
	"servers": [ {
		"count": 3,
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

echo > $LOG_FILE
# this test is not concerned with starting 'over the top'
# of an already running instance, so we kill it all first
kill_owner 9001
for PORT in $PORTS; do
	kill_owner $PORT
done

$ROOT/bin/shepherd -v -o $LOG_FILE -f $JSON_FILE -d -p $PID_FILE
sleep 4
PID=`cat $PID_FILE`
for PORT in $PORTS; do
	check_output $PORT "{\"PORT\": $PORT, \"TOKEN\": \"123456\"}" 
done
kill -2 $PID || echo "Failed to kill pid:" $PID
rm -f $PID_FILE $JSON_FILE $LOG_FILE
