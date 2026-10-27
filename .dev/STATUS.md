# Current status

Current step: 0007 done — plan for self-hosted native compiler (see 0007)
Next step:    0008 — compiler front end in GPLM (core/*.gp)

Go code now lives in `bootstrap/` (built as build/kaizo-go) and is used only to bootstrap.

## Toolchain
Until step 0010: Go >= 1.22 (stdlib only) for bootstrap/, make. `make core` builds build/kaizo-go. Origin machine had:
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
