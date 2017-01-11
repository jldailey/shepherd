#!/bin/bash

ROOT=`dirname $0`/..
source $ROOT/test/common.sh

echo '
{
	"workers": [ {
		"count": 2,
		"cd": "test/server",
		"command": "node worker.js"
	} ],
	"admin": { "port": 9001 },
	"nginx": { "enabled": false },
	"rabbitmq": { "enabled": false }
}
' > $JSON_FILE

kill_owner 9001

shepherd_start
PID=`cat $PID_FILE`
CHILDREN=`ps -eo pid,ppid,command | grep 'node\s' | grep -v grep | wc -l`
shepherd_stop
if [ "$CHILDREN" -ne 7 ]; then
	echo "FAIL: Expected 7 children, got '$CHILDREN'" 'from `ps -eo pid,ppid,command | grep node\s | grep -v grep`'
	exit 1
else
	echo "PASS"
fi
