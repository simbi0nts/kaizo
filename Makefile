# Kaizo build. No host language: the committed seed binary compiles the GPLM core.
SEED   := seed/kaizo
KAIZO  := build/kaizo
SUITES := tests/selftest.gp libs/rand libs/http libs/map apps/snake/main.gp apps/hello-web/main.gp

.PHONY: all core test selfhost e2e seed clean
all: core test

core: $(KAIZO)
$(KAIZO): $(wildcard core/*.gp core/rt/*.gp libs/map/*.gp)
	@mkdir -p build
	$(SEED) build core -o $(KAIZO)

test: core
	@for s in $(SUITES); do $(KAIZO) test $$s || exit 1; done

# the core must reproduce itself byte for byte
selfhost: core
	$(KAIZO) build core -o build/kaizo-next
	cmp $(KAIZO) build/kaizo-next && echo "fixpoint ok"

e2e: core
	./tests/e2e.sh

# refresh the seed after a change to the core (run selfhost first)
seed: selfhost
	cp $(KAIZO) $(SEED) && cd seed && sha256sum kaizo > kaizo.sha256

clean:
	rm -rf build
