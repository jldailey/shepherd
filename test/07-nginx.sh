#!/bin/bash

ROOT=`dirname $0`/..
source $ROOT/test/common.sh

echo '
{
	servers: [ {
		count: 3
		port: 9002
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
PORTS="9002 9003 9004"

# this test is not concerned with starting 'over the top'
# of an already running instance, so we kill it all first
kill_owner 9001
for PORT in $PORTS; do
	kill_owner $PORT
done

shepherd_start
sleep 3
for PORT in $PORTS; do
	check_output $PORT
done
shepherd_stop
EX=/tmp/07-nginx.config.expected
echo "upstream shepherd_pool {"              > $EX
echo "	"                                   >> $EX
for PORT in $PORTS; do
	echo "	server 127.0.0.1:$PORT weight=1;" >> $EX; done
echo "	"                                   >> $EX
echo "	keepalive 32;"                      >> $EX
echo -n "}"                                 >> $EX

git diff $EX /tmp/07-nginx.config
ret=$?
if [ $ret == 0 ]; then
	echo PASS
	rm $EX /tmp/07-nginx.config
else
	echo "FAIL"
fi
