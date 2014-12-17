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
PID=`cat $PID_FILE`
echo "Asking to reload via http://localhost:9001/reload"
before=$(get_owners 9003)
curl -u demo:demo -4 -s 'http://localhost:9001/reload' &> /dev/null
echo -n "Waiting"
for i in `seq 1 6`; do
	echo -n "...$i"
	sleep 1
done
assert_notequal "$before" "$(get_owners 9003)"
echo " seconds."
for PORT in $PORTS; do
	check_output $PORT
done

shepherd_stop
