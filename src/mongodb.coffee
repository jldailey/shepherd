MongoClient = require('mongodb').MongoClient
$ = require 'bling'

# The database connection has two phases: connected, and prepared
connected = $.Promise()
prepared = $.Promise()

connect = (url) -> # make the network connection to the database
	MongoClient.connect url, (err, db) ->
		if err then connected.reject err
		else connected.resolve db
	connected

prepare = (opts, db) -> # init the capped collection, when done fire the 'prepared' promise
	db.createCollection opts.collection, { capped: true, size: opts.size }, (err) ->
		if err then prepared.reject err
		else prepared.resolve(db)
	prepared

module.exports.createWriteStream = (opts) ->
	prepared.wait (err, db) ->
		if err then console.error "Failed to prepare MongoDB collection:", err
	connect(opts.url).then (db) ->
		prepare opts, db
	return {
		write: (data, enc) ->
			ts = $.now # save the timestamp first
			# if the connection isn't prepared, queue up the write for when it is
			prepared.then (db) ->
				db.collection(opts.collection).insert { ts, d: data, e: enc }, { safe: false }
	}
			
