# Step 0028 — Haiku GPLM re-run after the step-0027 fixes
Date: 2026-10-28
Status: done

## Why
Step 0027 found three Haiku GPLM failures (2× inline `if` without `end`, 1× C-style division on
Euclidean `div`) and changed the missing-`end` diagnostic and two lines of LANGUAGE.md. This step
measures whether those changes remove the failures.

## What was done
12 fresh Haiku agents, GPLM arm only, batch-2 specs × 3 runs, the updated reference in the prompt,
same protocol. Python baseline: step 0027 (12/12 first try). results.jsonl batch `batch2h2`;
programs in `evals/runs/2026-10-28-batch2h2/`. (One agent, calc r3, hit the session usage limit after
answering; its program was judged, its usage is missing.)

## Results
| | first-try solved | solved | chars vs Python | total tokens vs Python | time vs Python |
|---|---:|---:|---:|---:|---:|
| GPLM, step 0027 | 9/12 | 12/12 | 1.50x | 1.44x | 3.02x |
| GPLM, this step | **10/12** | 12/12 | 1.30x | 1.38x | 2.58x |
| Python (0027) | 12/12 | 12/12 | 1x | 1x | 1x |

- The targeted mistakes are gone: 0 inline-`if`-without-`end` (all 12 programs wrote
  `exit(if c then 1 else 0 end)` or avoided it), 0 division errors (all calc runs used the
  documented abs-and-sign approach).
- Two new first-answer failures, both *also* Python habits the language rejects, both fixed in one
  round from the diagnostics:
  1. calc r2: `let OPS = [...]` → `expected a lowercase name after let, found "OPS"`.
  2. csvsum r2: `if list_contains(...) == false then` → `expected "then" after if condition,
     found "="`.

## Reading the result (honestly)
- Targeted reference/diagnostic fixes work: each named mistake disappeared. But the error *class*
  remains — "Python habits that GPLM's syntax rejects" — and new instances replace the fixed ones.
  10/12 vs 9/12 is within noise; GPLM still trails Python's 12/12 on these specs.
- Size and time gaps shrank (1.50x→1.30x chars, 3.0x→2.6x time) but with 3 runs per spec this is
  within the run-to-run range observed in step 0026.
- Every GPLM error so far is caught by `kaizo check` and fixed in one round; none reached run time
  undetected. Python had no errors at all on these specs, so the checker has nothing to beat.

## Changes made from the findings
- `op_hint`: when the parser stops at `=`, `==`, `!=`, `<`, `+`, `&&` ... the hint says
  "GPLM has no operators: comparisons and arithmetic are calls, e.g. eq(a, b), ...".
- An uppercase name where a lowercase one is required: hint
  "values, functions and constants are lower_snake: write ops, not OPS".
- tests/type_errors/operator_eq.gp, upper_let.gp (22 wrong programs now). Seed refreshed.

## Next
- The remaining gap comes from GPLM looking unlike what models know. Either keep closing the
  habit list (diminishing returns, each fix measured), or test where the checker should win:
  specs with Python-typical errors (None/Optional handling, missed cases in state machines, type
  confusion across modules, modifying an existing multi-file program).
