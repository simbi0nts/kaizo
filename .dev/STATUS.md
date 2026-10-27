# Current status

Current step: 0005 done — both test projects pass (Snake, Hello web 2a)
Next step:    not chosen yet, see "Proposed next steps"

## Quick check
```
make test   # 32 GPLM tests: core, libs, apps
make e2e    # standalone builds + HTTP + pty Snake checks
```

## Proposed next steps (human picks)
1. **Blind test** (most valuable for the theory): a fresh agent gets only `core/LANGUAGE.md`
   and a new app spec, writes it in GPLM; count checker/runtime errors and fix rounds.
2. Static type checker (generics, Fn types with effects → closes the handler-effect gap).
3. 2b: mini text browser using `libs/http` (needs an HTTP *client* part + tcp_connect).
4. Content-hash lockfile for libraries (Theory 1 "shared with other agents").

## Toolchain
Go >= 1.22 (stdlib only), make. `make core` builds build/kaizo. Origin machine had:
gcc 15.2, go 1.26, python 3.14, node 22; linux/amd64.

## Layout
```
specs.md        human-owned concept, never edited by agents
.dev/           step log (this folder)
core/           the single core binary (interpreter + builder)
libs/           optional shared libraries written in GPLM
apps/snake/     test project 1
apps/hello-web/ test project 2
```
