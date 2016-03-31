#!/bin/sh

SHEP="coffee src/client/index.coffee"
SHEPD="coffee src/daemon/index.coffee"

$SHEPD stop && \
	$SHEPD start &
sleep 3
$SHEP status
sleep 1
$SHEP log --tee --url file://$HOME/Projects/shepherd/src/test.log
$SHEP add --group api --cd test/server --exec 'node app.js' -n 4 --port 8000
$SHEP enable --group api
sleep 3
$SHEP status
sleep 2
exit 0

