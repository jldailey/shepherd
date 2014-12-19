JS_FILES=$(shell find src -name \*.coffee | sed -e 's/src/lib/' -e 's/\.coffee/.js/')
PASS_FILES=$(shell ls test/*.sh | grep -v "common.sh" | sed -e 's/\.sh/.sh.pass/' )

all: $(JS_FILES)

lib/%.js: src/%.coffee
	@echo "Compiling $<..."
	@(o=`dirname $< | sed -e 's/src/lib/'` && \
		mkdir -p $$o && \
		coffee -o $$o -c $<)

test: all $(PASS_FILES)

test/%.sh.pass: test/%.sh $(JS_FILES)
	./$< && touch $@

test-serve: all
	cd test/server && ../../bin/shepherd -v -f shepherd.json

clean: clean-test
	rm -rf lib/*

clean-test:
	rm -f test/*.pass

.PHONY: all test clean clean-test test-reload
