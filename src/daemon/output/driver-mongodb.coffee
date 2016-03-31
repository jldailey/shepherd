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

usage = (msg) ->
		console.error "Error: Must specify a mongodb url as mongodb://<host>[:port]/database/collection?size=<bytes> (#{msg})"

module.exports.createWriteStreams = (url) ->
	[database, collection] = url.path.split('/')
	size = parseInt url.query.size, 10
	unless collection?.length > 0
		usage("invalid or missing collection argument")
		return [ process.stdout, process.stderr ]
	unless isFinite(size) and $.is('number', size) and 0 < size
		usage("invalid or missing size argument")
		return [ process.stdout, process.stderr ]
	prepared.wait (err, db) ->
		if err then console.error "Failed to prepare MongoDB collection:", err
	connect($.URL.stringify(url)).then (db) ->
		prepare collection, size, db
	
	stdout = new stream.Writable write: (data, enc, cb) ->
		ts = $.now # save the timestamp first
		# if the connection isn't prepared, queue up the write for when it is
		prepared.then (db) ->
			db.collection(collection).insert { ts, d: data.toString(enc) }, { safe: false }, cb

	return [ stdout, stdout ]
