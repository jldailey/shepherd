JS_FILES=$(shell ls src/*.coffee | sed -e 's/src/lib/' -e 's/coffee/js/')
PASS_FILES=$(shell ls test/*.sh | grep -v "common.sh" | sed -e 's/.sh/.sh.pass/' )

all: $(JS_FILES)

lib/%.js: src/%.coffee
	coffee -o lib -c $<

test: all $(PASS_FILES)

test/%.sh.pass: test/%.sh all
	./$< && touch $@

clean-test:
	rm -f test/*.pass

.PHONY: test
