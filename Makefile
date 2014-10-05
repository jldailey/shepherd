JS_FILES=$(shell ls src/*.coffee | sed -e 's/src/lib/' -e 's/coffee/js/')

all: $(JS_FILES)

lib/%.js: src/%.coffee
	coffee -o lib -c $<

test: $(JS_FILES)
	./test/simple-startup.sh
	./test/restart-single.sh

.PHONY: test
