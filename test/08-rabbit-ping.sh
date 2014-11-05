#!/bin/bash

ROOT=`dirname $0`/..
source $ROOT/test/common.sh
FULL="${PWD}/${ROOT}"

AMQP_URL="amqp://test:test@130.211.112.10:5672"
AMQP_CHANNEL="test"

echo "
{
	servers: [ {
		count: 3
		port: 9002
		cd: test/server
		command: node app.js
	} ],
	admin: { port: 9001 },
	nginx: { enabled: false },
	rabbitmq: {
		enabled: true
		url: "$AMQP_URL"
		channel: "$AMQP_CHANNEL"
	}
}
" > $JSON_FILE
PORTS="9002 9003 9004"

echo "
Rabbit = require '$FULL/src/rabbit.coffee'

Rabbit.connect('$AMQP_URL').then ->
	count = 0
	setTimeout (-> process.exit 1), 1000
	Rabbit.subscribe '$AMQP_CHANNEL', (msg) ->
		if msg.op is 'pong'
			console.log 'PASS'
			process.exit 0
	setTimeout (->
		Rabbit.publish '$AMQP_CHANNEL', { op: 'ping' }
	), 200
" > $COFFEE_FILE

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
coffee $COFFEE_FILE || exit 1
shepherd_stop
