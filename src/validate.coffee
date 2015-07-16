$ = require 'bling'
Fs = require 'fs'
JSV = require('JSV').JSV.createEnvironment("json-schema-draft-03")
CSON = require('cson')

Validate = module.exports

schemaFile = -> $.config.get "SHEPHERD_SCHEMA", "src/schema.cson"

readable = (err) ->
	path = $(err.uri.split '#').last().replace(/^\//,'').split(/\//)
	field = $(path).last()
	item = $(path).slice(0,-1).join(".")
	if err.attribute is 'type'
		err.message += " (#{err.details[0]})"
	return "In \"#{item}\", field \"#{field}\" failed validation: #{err.message}"

Validate.isValidConfig = (obj) ->
	schema = CSON.parseFile schemaFile()
	return JSV.validate(obj, schema).errors.map readable

if require.main is module
	die = (err) ->
		console.error err
		process.exit 1
	testData = [
		{ }
			[ 'In "", field "servers" failed validation: Property is required' ]

		{ servers: [ { } ] }
			[ 'In "servers.0", field "command" failed validation: Property is required' ]

		{ servers: [ { command: "echo" } ] }
			[ ]

		{ servers: [ { command: "echo" } ], nginx: { enabled: "false" } }
			[ 'In "nginx", field "enabled" failed validation: Instance is not a required type (boolean)' ]

		{ servers: [ { command: "echo" } ], admin: { enabled: "false" } }
			[ 'In "admin", field "enabled" failed validation: Instance is not a required type (boolean)' ]

		{ servers: [ { command: "echo" } ], admin: { port: "false" } }
			[ 'In "admin", field "port" failed validation: Instance is not a required type (number)' ]

		{ servers: [ { command: "echo" } ], rabbitmq: { enabled: "false" } }
			[ 'In "rabbitmq", field "enabled" failed validation: Instance is not a required type (boolean)' ]

		{ servers: [ { command: "echo" } ], rabbitmq: { url: null } }
			[ 'In "rabbitmq", field "url" failed validation: Instance is not a required type (string)' ]

	]
	assert = require 'assert'
	for i in [0...testData.length - 1] by 2
		errors = Validate.isValidConfig testData[i]
		assert.deepEqual errors, testData[i+1]
