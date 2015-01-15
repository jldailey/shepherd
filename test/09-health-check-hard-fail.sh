#!/bin/bash

ROOT=`dirname $0`/..
source $ROOT/test/common.sh

echo '
{
	"servers": [ {
		"count": 3,
		"port": 9002,
		"cd": "test/server",
		"command": "node app.js",
		"check": {
			"enabled": true
			"url": "/health-check"
			"status": 200
			"contains": "IM OK"
			"timeout": 1000
			"interval": 5000
		}
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
echo Waiting for health-check to fail...
# the health-check url will get hit every 10 seconds, will pass 3 times
# then on the 4th will either timeout (+1 second) or fail fast
# in either case, by 40 seconds, the process should have been restarted
sleep 20
after=$(get_owners 9003)
if [ "$before" != "$after" ]; then
	echo "PASS"
else
	echo "FAIL: '${before}' should not == '${after}'"
fi
shepherd_stop
