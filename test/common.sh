
function kill_owner {
	local port=$1
	echo -n PORT: ${port}
	local pid=`lsof -i :${port} | grep :${port} | awk '{print $2}'`
	echo -n " PID:" ${pid}
	if [ -n "${pid}" ]; then
		echo "Killing..."
		kill -9 ${pid}
	else
		echo
	fi
}
