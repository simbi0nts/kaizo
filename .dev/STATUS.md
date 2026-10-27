# Current status

Current step: 0008 done — GPLM front end (lexer, parser, checker)
Next step:    0009 — native back end

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
