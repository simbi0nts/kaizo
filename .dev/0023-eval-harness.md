# Step 0023 — Eval harness and first batch (GPLM vs Python)
Date: 2026-10-27
Status: done

## Goal
Phase 2 of ROADMAP.md: measure the theory continuously instead of by one-off blind tests.

## What was built (`evals/`)
- 4 specs, each with `spec.md`, `reference.py` and hidden `cases/`: wordfreq (from step 0016),
  roman (both directions, canonical-form validation, 26 cases), life (Game of Life from stdin,
  60x60x100 performance case), ledger (CSV transfers, error line numbers, 10,000-line case).
- `score.sh` (stdout+stderr and exit code vs the reference), `judge.sh` (the protocol's step 2 for
  GPLM or Python: check/syntax → own tests → hidden test, prints the fix-round feedback),
  `extract.py`, `run_py_tests.py`, `report.py`, arm prompts `arms/gplm.md` / `arms/python.md`,
  protocol in `evals/README.md`. Validated: references pass their cases; the GPLM wordfreq of
  step 0016 passes 7/7.

## Batch 1 (8 fresh agents, Claude Opus 5.5, no tools except reading their own prompt)
| spec | arm | total tokens¹ | time s | lines | fix rounds | hidden |
|---|---|---:|---:|---:|---:|---:|
| wordfreq | GPLM | 54,379 | 27.8 | 98 | 0 | 7/7 |
| wordfreq | Python | 48,360 | 12.7 | 73 | 0 | 7/7 |
| roman | GPLM | 54,932 | 36.3 | 141 | 0 | 26/26 |
| roman | Python | 48,585 | 16.0 | 98 | 0 | 26/26 |
| life | GPLM | 56,123 | 44.9 | 159 | 0 | 7/7 |
| life | Python | 49,028 | 18.8 | 153 | 0 | 7/7 |
| ledger | GPLM | 56,022 | 43.3 | 171 | 0 | 5/5 |
| ledger | Python | 48,928 | 21.3 | 122 | 0 | 5/5 |
¹ includes the prompt; the GPLM prompt carries LANGUAGE.md (~6k tokens), so most of the
~+6.5k difference is reading the reference, not writing code.

## Reading the result (honestly)
- **Correctness: a tie at the ceiling.** 8/8 solved on the first attempt, 0 checker errors,
  0 fix rounds in both languages. These specs are too easy to separate the languages on
  correctness — the batch cannot confirm or refute the theory's main claim.
- **Cost: GPLM is more expensive.** ~2.2x wall time and ~1.3x lines (no loops, no operators,
  explicit `end`s); token totals +13%, mostly the language reference in the prompt.
- **No false friends**: no operators, no `for`, no `return` appeared in any GPLM answer; all four
  used tail recursion, `match` on lists and `list_fold` idiomatically, and every program type-checked.

## Next
- Harder specs where mistakes are likely (stateful protocols, many edge cases, larger programs),
  so correctness can differ; measure output tokens separately from prompt tokens.
- Use the cost finding: candidates to shorten GPLM programs (e.g. loops over ranges, string
  interpolation) — each would be a language step citing these numbers.
