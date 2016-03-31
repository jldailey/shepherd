#!/bin/sh

SHEP="coffee src/client/index.coffee"
SHEPD="coffee src/daemon/index.coffee"

$SHEPD stop && \
	$SHEPD start &
sleep 1
$SHEP add --group api --cd test/server --exec 'node app.js' -n 4 --port 8000
$SHEP enable --group api-1
sleep 1
$SHEP status
sleep 2
$SHEPD stop

