# Build the core and run every GPLM test suite.
KAIZO := build/kaizo-go

.PHONY: all core test e2e clean
all: core test

core:
	cd bootstrap && go build -o ../$(KAIZO) .

test: core
	$(KAIZO) test core/selftest.gp libs/rand libs/http libs/map apps/snake/main.gp apps/hello-web/main.gp

e2e: core
	./tests/e2e.sh

clean:
	rm -rf build
