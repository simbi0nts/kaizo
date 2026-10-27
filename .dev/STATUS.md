# Current status

Current step: 0006 done — blind test: todo-cli written from LANGUAGE.md alone, 0 fix rounds
Next step:    not chosen yet, see "Proposed next steps"

## Quick check
```
make test   # 37 GPLM tests: core, libs, apps
make e2e    # standalone builds + HTTP + pty Snake checks
```

## Proposed next steps (human picks)
1. LANGUAGE.md doc gaps + checker hints from 0006 ("did you mean", self-recursion, record patterns).
2. Static type checker (generics, Fn types with effects → closes the handler-effect gap).
3. 2b: mini text browser using `libs/http` (needs an HTTP *client* part + tcp_connect).
4. Content-hash lockfile for libraries (Theory 1 "shared with other agents").
5. O(1) amortized list append (0006: append-accumulate is O(n²), 32k items = 17 s).
6. Repeat the blind test with a different model and a harder spec.

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
apps/todo-cli/  blind-test app (step 0006)
```
