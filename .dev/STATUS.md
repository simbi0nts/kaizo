# Current status

Current step: 0028 done — Haiku GPLM re-run: 10/12 first try (targeted errors gone, new habits); operator/naming hints
Next step:    specs where Python-typical errors appear (None, missed cases, multi-file edits), or Phase 3

## Reserved steps
0029 — T1a: infix operators and grouping (this session)

## Quick check
```
make all        # seed/kaizo builds build/kaizo, then 34 native tests
make selfhost   # core rebuilds itself byte-identically
make e2e        # standalone Snake + Hello web end-to-end
```

## Cross-platform
`kaizo build app.gp -o app --target windows-x64|macos-x64|macos-arm64|linux-x64`. CI workflow:
`.github/workflows/ci.yml` (Linux cross-builds; Windows/macOS runners run `tests/ci_platform.sh`).

## Proposed next steps (human picks)
2. Static type checker (closes the gaps found by the blind test, step 0006 branch).
3. Repeat the blind test against the native core.
4. 2b mini text browser; content-hash lockfile for libraries.

## Toolchain
Linux x86-64 and `make`. Nothing else: `seed/kaizo` (committed Linux binary) builds the core.
On Windows/macOS: take kaizo from the CI artifact (or cross-build it on Linux) and run it directly.
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
