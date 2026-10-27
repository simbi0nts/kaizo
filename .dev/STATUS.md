# Current status

Current step: 0011 — cross-platform work, phase A done
Next step:    0011 phase B — IR, PIC, OS-layer split (Linux)

## Quick check
```
make all        # seed/kaizo builds build/kaizo, then 34 native tests
make selfhost   # core rebuilds itself byte-identically
make e2e        # standalone Snake + Hello web end-to-end
```

## Proposed next steps (human picks)
1. Garbage collector (needed for long-running servers).
2. Static type checker (closes the gaps found by the blind test, step 0006 branch).
3. Repeat the blind test against the native core.
4. 2b mini text browser; content-hash lockfile for libraries.

## Toolchain
Linux x86-64 and `make`. Nothing else: `seed/kaizo` (committed binary) builds the core.
For e2e tests: curl, python3. The Go bootstrap lives only in git history (tag `bootstrap-go`).

## Layout
```
specs.md        human-owned concept, never edited by agents
.dev/           step log (this folder)
core/           the core in GPLM: compiler (front end, x86-64 back end) + rt/ runtime
seed/           committed kaizo binary used to build core/ (self-hosting seed)
tests/          core self-test + end-to-end scripts
libs/           optional shared libraries written in GPLM
apps/snake/     test project 1
apps/hello-web/ test project 2
```
