if config.mongodb?.enabled
$ = require 'bling'

# The database connection has two phases: connected, and prepared
connected = $.Promise()
prepared = $.Promise()

connect = (url) -> # make the network connection to the database
	require('mongodb').MongoClient.connect url, (err, db) ->
		if err then connected.reject err
		else connected.resolve db
	connected

prepare = (collection, size, db) -> # init the capped collection, when done fire the 'prepared' promise
	db.createCollection collection, { capped: true, size: size }, (err) ->
		if err then prepared.reject err
		else prepared.resolve(db)
	prepared

module.exports.createWriteStream = (url) ->
	[database, collection] = url.path.split('/')
	size = parseInt url.query.size, 10
	prepared.wait (err, db) ->
		if err then console.error "Failed to prepare MongoDB collection:", err
	connect($.URL.stringify(url)).then (db) ->
		prepare collection, size, db

	new stream.Writable write: (data, enc, cb) ->
		ts = $.now # save the timestamp first
		# if the connection isn't prepared, queue up the write for when it is
		prepared.then (db) ->
			db.collection(opts.collection).insert { ts, d: data.toString(enc) }, { safe: false }, cb
