
JSON_FILE=/tmp/${TEST_NAME}.json
PID_FILE=/tmp/${TEST_NAME}.pid
LOG_FILE=/tmp/${TEST_NAME}.log

function shepherd_start {
	echo Launching shepherd...
	$ROOT/bin/shepherd -v -o $LOG_FILE -f $JSON_FILE -d -p $PID_FILE
	sleep 4
	return `cat $PID_FILE`
}

function shepherd_stop {
	echo "Stopping shepherd..."
	PID=`cat $PID_FILE`
	kill -2 $PID || echo "Failed to kill shepherd pid:" $PID
	rm -f $PID_FILE $JSON_FILE $LOG_FILE
}

function kill_owner {
	local port=$1
	local pid=`lsof -Pni :${port} | grep :${port} | awk '{print $2}'`
	if [ -n "${pid}" ]; then
		echo "Killing $PID (to clear port $PORT)"
		kill -9 ${pid}
	fi
}

function check_output {
	local port=$1
	local expected=$2
	local output=`curl -s http://localhost:$port/`
	if [ "$output" != "$expected" ]; then
		echo "Unexpected output: '" $output "' expected: '" $expected "'"
		shepherd_stop
		exit 1
	else
		echo "PASS"
	fi
}
