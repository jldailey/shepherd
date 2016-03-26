$ = require 'bling'
Fs = require 'fs'

class Journal extends $.EventEmitter
	@codec = $.TNET
	constructor: (@path, @offset) ->
		Fs.watch @path, { persistent: false }, $.debounce 10, (evt, filename) =>
			stat = Fs.statSync(filename)
			if stat.size > offset
				fd = Fs.openSync(filename, "r")
				buf = new Buffer(2)
				Fs.readSync(fd, buf, 0, 2, offset)
				size = buf.readUInt16LE(0)
				buf = new Buffer(size)
				Fs.readSync(fd, buf, 0, size, offset+2)
				offset += size + 2
				Fs.closeSync(fd)
				@emit 'data', Journal.codec.parse buf.toString()
	append: (obj) ->
		s = Journal.codec.stringify obj
		n = 2 + Buffer.bytesLength(s,	"utf8")
		buf = new Buffer(n)
		buf.writeUInt16LE(n - 2, 0)
		buf.write(s, 2)
		Fs.appendFileSync(@path, buf)
