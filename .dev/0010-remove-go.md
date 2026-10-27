# Step 0010 — Go removed; the process repeated on the self-hosted core
Date: 2026-10-27
Status: done

## Goal
Finish "make the language from scratch": no host language left in the repository, and both
test projects pass again on the new core.

## What was done
- `bootstrap/` (Go) deleted. Its last commit is tagged **`bootstrap-go`** (96415a8): the seed can
  always be re-derived from source:
  `git checkout bootstrap-go && (cd bootstrap && go build -o ../build/kaizo-go .) &&
  build/kaizo-go run core build core -o build/kaizo1` gives the same bytes as `seed/kaizo`
  (shown in step 0009: kaizo1 == kaizo2).
- `seed/kaizo` (783 KB) + `seed/kaizo.sha256` committed: the fixpoint binary from step 0009.
- `Makefile`: `make core` (seed builds the core), `make test` (34 tests, native), `make selfhost`
  (core rebuilds itself and must be byte-identical), `make e2e`, `make seed`.
- `core/LANGUAGE.md` updated to v1 (new builtins, `fs`/`proc` effects, 63-bit Int, no GC yet).

## Repeat of the process (both test projects on the new core)
| Check | Result |
|-------|--------|
| GPLM test suites (native) | 34/34 pass |
| Snake built natively (129 KB static ELF) | pty e2e 7/7: frame, keys, `q` → Game over, exit 0, termios + cursor restored after `q` and after Ctrl+C (signal handler), dies at wall |
| Hello web built natively (113 KB static ELF) | e2e 6/6: 200 + content type + h1, 404, garbage → 400, 20 sequential requests |
| Self-hosting | fixpoint holds (`make selfhost`) |
| Go / C / other host code in repo | none (`git ls-files` has no .go); Python only in the test harness `tests/snake_pty.py` |

App sources were not changed at all between the Go core and the native core.

## How to verify on a fresh machine (Linux x86-64; needs only make, plus curl/python3 for e2e)
```
make all        # seed -> build/kaizo, then all test suites
make selfhost   # fixpoint ok
make e2e
```

## Known gaps / next candidates
No GC (self-compile peaks at 256 MB); no static type checker; runtime errors inside
library builtins have no source position; Linux x86-64 only.
