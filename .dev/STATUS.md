# Current status

Current step: 0001 (proposal, waiting for human decisions — see "Open questions" there)
Next step:    0002 — minimal core: lexer + parser + evaluator, `hello` to stdout

## Toolchain
Not fixed yet (decided in step 0001). Available on the origin machine:
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
