#!/bin/bash

ROOT=`dirname $0`/..
source $ROOT/test/common.sh

echo '
{
	"servers": [ {
		"count": 3,
		"port": 9002,
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
for PORT in $PORTS; do
	check_output $PORT
done
before=$(get_owners 9003)
kill_owner 9003
sleep 3
check_output 9003 
after=$(get_owners 9003)
if [ "$before" != "$after" ]; then
	echo "PASS"
else
	echo "FAIL: '${before}' != '${after}'"
fi
shepherd_stop
