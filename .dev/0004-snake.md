# Step 0004 — Test project 1: Snake
Date: 2026-10-27
Status: done (all acceptance criteria in apps/snake/ACCEPTANCE.md pass)

## Goal
Write Snake in GPLM only and verify every acceptance criterion automatically.

## What was done
- `libs/rand/rand.gp` — pure seedable LCG (`seeded`, `next`, `below`) + 3 tests.
  First shared library; pure, so food placement is reproducible in tests.
- `apps/snake/main.gp` (~250 lines, no host code) — pure logic (`tick`, `turn`, `on_key`,
  `place_food`, `render`) + thin effectful loop (`read_keys`, `game_loop`, `main`).
  14 GPLM tests: move, turn, reverse ignored, two-quick-turns, eat+grow, wall death,
  self death, tail-vacating move, quit, seeded food, full board, render, arg parsing.
- `tests/snake_pty.py` — drives the real binary in a pseudo-terminal: frame rendered,
  keys, `q` → "Game over. Score: N" + exit 0, terminal flags + cursor restored after `q`
  and after Ctrl+C, snake dies at the wall unattended. (Python is only the test harness.)

## Acceptance criteria → evidence
| # | Criterion | Evidence |
|---|-----------|----------|
| 1 | `kaizo run` starts game | snake_pty.py with `build/kaizo run apps/snake/main.gp` |
| 2 | `kaizo build` → standalone | `build/snake` passes the same pty checks |
| 3 | 20x15 bordered, length 3, right | test "starts with…", frame capture |
| 4 | arrows/WASD, reverse ignored | tests "turn…", "reverse is ignored", "two quick turns…" |
| 5 | random free food, grow+score | tests "eating grows…", "food placement…" |
| 6 | wall/self → Game over | tests + pty "dies at the wall" |
| 7 | q quits, terminal restored | pty: q, Ctrl+C, termios compared before/after |
| 8 | fixed tick 150 ms | `game_loop` sleeps `tick - elapsed`, independent of keys |

## Observations about the language (input for later steps)
- Writing went smoothly; all tests passed on the first run. The checker caught nothing
  because there were no mistakes — the real test is a *fresh* agent that only reads
  `core/LANGUAGE.md` (the author of the core knows it too well). Proposed as a later step.
- Friction: binary `str_cat` → many `str_join([...], "")`; nested `and(and(..), and(..))`.
  Candidates: `str_concat(list)` / `all(list)` / `any(list)` — decide before adding (one way per thing).
- Non-tty start gives a clean message instead of a crash (Result from `term_raw`).

## How to verify
```
make core
build/kaizo test libs/rand apps/snake/main.gp
build/kaizo build apps/snake/main.gp -o build/snake && python3 tests/snake_pty.py build/snake
build/snake            # play
```

## Next step
0005 — Test project 2a: Hello web (`libs/http` + `apps/hello-web`).
