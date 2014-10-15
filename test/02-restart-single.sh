#!/bin/bash

ROOT=`dirname $0`/..
source $ROOT/test/common.sh

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
PORTS="8001 8002 8003"

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
before=$(get_owners 8002)
kill_owner 8002
sleep 3
check_output 8002 
after=$(get_owners 8002)
if [ "$before" != "$after" ]; then
	echo "PASS"
else
	echo "FAIL: '${before}' != '${after}'"
fi
shepherd_stop
