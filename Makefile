# Build the core and run every GPLM test suite.
KAIZO := build/kaizo

.PHONY: all core test e2e clean
all: core test

core:
	cd core && go build -o ../$(KAIZO) .

test: core
	$(KAIZO) test core/selftest.gp libs/rand libs/http apps/snake/main.gp apps/hello-web/main.gp

e2e: core
	./tests/e2e.sh

clean:
	rm -rf build
