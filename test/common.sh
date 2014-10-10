
ROOT=`dirname $0`/..
TEST_NAME=`basename $0 | sed s/\.sh//`
JSON_FILE=/tmp/${TEST_NAME}.json
PID_FILE=/tmp/${TEST_NAME}.pid
LOG_FILE=/tmp/${TEST_NAME}.log
echo > $LOG_FILE

VERBOSE=false
if [ "$1" == "verbose" ]; then
	VERBOSE=true
fi

function log {
	if $VERBOSE; then echo $1; fi
}

mkdir -p `dirname $LOG_FILE`
touch $LOG_FILE

function shepherd_start {
	log "Launching shepherd..."
	$ROOT/bin/shepherd -v -d -o $LOG_FILE -f $JSON_FILE -p $PID_FILE
	sleep 4
	return `cat $PID_FILE`
}

function shepherd_stop {
	log "Stopping shepherd..."
	PID=`cat $PID_FILE`
	kill -2 $PID || log "Failed to kill shepherd pid:" $PID
	rm -f $PID_FILE $JSON_FILE
	if $VERBOSE; then
		kill %1
	fi
}

function kill_owner {
	local port=$1
	local pid=`lsof -Pni :${port} | grep :${port} | awk '{print $2}'`
	if [ -n "${pid}" ]; then
		log "Killing $PID (to clear port $PORT)"
		kill -9 ${pid}
	fi
}

function check_output {
	local port=$1
	local expected="{\"PORT\": $port, \"TOKEN\": \"123456\"}"
	local output=`curl -s http://localhost:$port/`
	if [ "$output" != "$expected" ]; then
		echo "Unexpected output: '" $output "' expected: '" $expected "'"
		shepherd_stop
		exit 1
	else
		echo "PASS"
	fi
}
