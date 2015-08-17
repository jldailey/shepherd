$ = require 'bling'
Fs = require 'fs'
JSV = require('JSV').JSV.createEnvironment("json-schema-draft-03")
CSON = require('cson')

Validate = module.exports

schemaFile = -> $.config.get "SHEPHERD_SCHEMA", __dirname + "/src/schema.cson"

readableError = (err) ->
	path = $(err.uri.split '#').last().replace(/^\//,'').split(/\//)
	field = $(path).last()
	item = $(path).slice(0,-1).join(".")
	message = err.message.replace("Instance is ","")
	if err.attribute is 'type'
		message += " (#{err.details[0]})"
	return "In \"#{item}\", field \"#{field}\" failed validation: #{message}"

isFileWritable = (file) ->
	try Fs.accessSync(file, Fs.W_OK)
	catch then return false
	return true

isFileCreatable = (file) ->
	path = $(file.split '/').slice(0,-1).join('/')
	try
		return false unless Fs.statSync(path).isDirectory()
		Fs.accessSync(path, Fs.W_OK)
	catch err then return false
	return true

isDirectory = (path) ->
	try return Fs.statSync(path).isDirectory()
	catch then return false

Validate.isValidConfig = (obj) ->
	schema = CSON.parseFile schemaFile()
	errors = JSV.validate(obj, schema).errors.map readableError
	return errors if errors.length

	# manual checks:
	# obj.nginx.config points to a writable file
	if obj.nginx?.enabled and obj.nginx?.config
		if (not isFileWritable obj.nginx.config) and (not isFileCreatable obj.nginx.config)
			return [ 'In "nginx", field "config" failed validation: file is not writable' ]

	# must specify at least one server or one worker
	if (not obj.servers) and (not obj.workers)
		return [ 'In "", field "servers" failed validation: must specify either "servers" or "workers"' ]

	# server and worker 'cd' values point to accessible directories
	for server,i in obj.servers ? []
		if server.cd and not isDirectory(server.cd)
			return [ "In \"servers.#{i}\", field \"cd\" failed validation: not a directory (#{server.cd})" ]
	
	for worker, i in obj.workers ? []
		if worker.cd and not isDirectory(worker.cd)
			return [ "In \"workers.#{i}\", field \"cd\" failed validation: not a directory (#{worker.cd})" ]

	# rabbitmq.url should be a parsable url with protocol "amqp"
	if obj.rabbitmq?.enabled and obj.rabbitmq?.url
		unless $.URL.parse(obj.rabbitmq.url)?.protocol is "amqp"
			return [ 'In "rabbitmq", field "url" failed validation: not a valid amqp:// URL' ]

	# TODO: server port ranges don't overlap
	return []

if require.main is module
	die = (err) ->
		console.error err
		process.exit 1
	testData = [
		{ }
			[ 'In "", field "servers" failed validation: must specify either "servers" or "workers"' ]

		{ servers: [ { } ] }
			[ 'In "servers.0", field "command" failed validation: Property is required' ]

		{ servers: [ { command: "echo" } ] }
			[ ]

		{ servers: [ { command: "echo" } ], nginx: { enabled: "false" } }
			[ 'In "nginx", field "enabled" failed validation: not a required type (boolean)' ]

		{ servers: [ { command: "echo" } ], admin: { enabled: "false" } }
			[ 'In "admin", field "enabled" failed validation: not a required type (boolean)' ]

		{ servers: [ { command: "echo" } ], admin: { port: "false" } }
			[ 'In "admin", field "port" failed validation: not a required type (number)' ]

		{ servers: [ { command: "echo" } ], rabbitmq: { enabled: "false" } }
			[ 'In "rabbitmq", field "enabled" failed validation: not a required type (boolean)' ]

		{ servers: [ { command: "echo" } ], rabbitmq: { url: null } }
			[ 'In "rabbitmq", field "url" failed validation: not a required type (string)' ]

		{ servers: [ { command: "echo" } ], rabbitmq: { enabled: true, url: "..."} }
			[ 'In "rabbitmq", field "url" failed validation: not a valid amqp:// URL' ]

		{ servers: [ { command: "echo" } ], nginx: { config: null } }
			[ 'In "nginx", field "config" failed validation: not a required type (string)' ]

		{ servers: [ { command: "echo" } ], nginx: { enabled: true, config: "..." } }
			[ 'In "nginx", field "config" failed validation: file is not writable' ]

		{ servers: [ { cd: "no_exist", command: "echo" } ] }
			[ 'In "servers.0", field "cd" failed validation: not a directory (no_exist)' ]

		{ servers: [ { cd: ".", command: "echo" } ] }
			[ ]

	]
	assert = require 'assert'
	for i in [0...testData.length - 1] by 2
		errors = Validate.isValidConfig testData[i]
		assert.deepEqual errors, testData[i+1]
