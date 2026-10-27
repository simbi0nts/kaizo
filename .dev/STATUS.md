# Current status

Current step: 0003 done
Next step:    0004 — Snake + libs/rand

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
