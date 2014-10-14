#!/bin/bash

ROOT=`dirname $0`/..
source $ROOT/test/common.sh

echo '
{
	servers: [ {
		count: 2
		port: 8001
		cd: test/server
		command: node app.js
	} ],
	workers: [ {
		count: 2,
		cd: test/server
		command: node worker.js
	} ]
	admin: { port: 9001 },
	nginx: {
		enabled: true
		config: /tmp/07-nginx.config
	}
	rabbitmq: { enabled: false }
}
' > $JSON_FILE
PORTS="8001 8002"

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
CHILDREN=`ps -eo pid,ppid,command | grep node | grep -v grep | wc -l`
shepherd_stop
if [ "$CHILDREN" -ne 9 ]; then
	echo "FAIL: Expected 9 children, got '$CHILDREN'"
	exit 1
else
	echo "PASS"
fi
