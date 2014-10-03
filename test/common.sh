
function kill_owner {
	local port=$1
	local pid=`lsof -i :${port} | grep :${port} | awk '{print $2}'`
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
	else
		echo "PASS"
	fi
}
