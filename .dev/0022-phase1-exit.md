# Step 0022 — Phase 1 exit: the blind-test mistakes are all caught before run time
Date: 2026-10-27
Status: done

## Change of plan
0022 was reserved for "RC skips Int values". That saves one test-and-branch per count update
(small), while the Phase 1 exit criterion of ROADMAP.md was still unmeasured. Measuring came first;
the RC optimisation moves to Phase 4 (performance).

## Measurement
Blind test v1 (step 0006) injected 11 typical LLM mistakes into apps/todo-cli; 8 were caught by
the checker, 3 reached run time. `tests/mutations.sh` replays those 3 automatically:

| Mistake | kaizo of step 0019 | kaizo now |
|---|---|---|
| `t.txt` instead of `t.text` | not caught (run time) | `31:62: type Todo has no field txt` |
| `str_cat("added ", list_len(items))` — forgot `show` | not caught (run time) | `69:59: type mismatch: expected String, got Int` |
| `fn after(...) -> String` returns `str_len(s)` | not caught (run time, symptom two calls away) | `12:3: type mismatch: expected String, got Int` (at the function itself) |

Result: **11 of 11** injected mistakes are rejected by `kaizo check` (was 8 of 11).
Plus the effect gap from step 0005 (a handler passed as a value) is closed (step 0021).
`tests/mutations.sh` is part of `make test`, next to the 16 `tests/type_errors`.

Also fixed: `tests/snake_pty.py` had a flaky check (the unattended snake sometimes eats food on its
way and ends with score 1).

## Phase 1 summary (0020–0022)
Inference-based static types (generics, records, lambdas typed from context), function types with
effects, 16 + 3 regression programs, cost +0.05 s on checking the compiler, no annotation added to
any existing program; the checker found 2 real problems in existing code (stale IR signatures,
fake socket in x11 tests).

## Next
Phase 2: 0023 — `kaizo eval` harness (specs + hidden tests, fresh agents, GPLM vs baseline).
