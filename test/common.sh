#!/bin/bash

ROOT=`dirname $0`/..
TEST_NAME=`basename $0 | sed s/\.sh//`
JSON_FILE=/tmp/${TEST_NAME}.json
COFFEE_FILE=/tmp/${TEST_NAME}.coffee
PID_FILE=/tmp/${TEST_NAME}.pid
LOG_FILE=/tmp/${TEST_NAME}.log
echo > $LOG_FILE

VERBOSE=false
if [ "$1" == "verbose" ]; then
	VERBOSE=true
fi

function log {
	if $VERBOSE; then echo $1; fi
	echo TEST: $1 >> $LOG_FILE
}

function assert_notequal {
	local a=$1
	local b=$2
	if [ "$a" != "$b" ]; then
		echo "PASS"
	else
		echo "FAIL: '$b' should != '$a'"
	fi
}

mkdir -p `dirname $LOG_FILE`
touch $LOG_FILE

function shepherd_start {
	log "Launching shepherd..."
	$ROOT/bin/shepherd -v -d -o $LOG_FILE -f $JSON_FILE -p $PID_FILE
	sleep 6
	return `cat $PID_FILE`
}

function shepherd_stop {
	log "Stopping shepherd..."
	curl -u demo:demo http://127.0.0.1:9001/stop &> /dev/null
	rm -f $PID_FILE $JSON_FILE $COFFEE_FILE
}

function kill_owner {
	local port=$1
	local pid=`lsof -Pni :${port} | grep :${port} | awk '{print $2}'`
	if [ -n "${pid}" ]; then
		log "Killing $pid (to clear port $port)"
		kill -9 ${pid}
	fi
}

function get_owners {
	local port=$1
	echo `lsof -Pni :${port} | grep :${port} | awk '{print $2}'`
}

function check_output {
	local port=$1
	local owner=$(get_owners $port)
	local expected="{\"PORT\": $port, \"PID\": \"$owner\"}"
	local output=`curl -s http://127.0.0.1:$port/`
	if [ "$output" != "$expected" ]; then
		echo "Unexpected output: '" $output "' expected: '" $expected "'"
		shepherd_stop
		exit 1
	else
		echo "PASS"
	fi
}

if [ "$0" == "./common.sh" ]; then
	port=$1
	echo Testing common.sh...
	owner=$(get_owners $port)
	echo $owner
fi
