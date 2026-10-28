# Step 0024 — Eval batch 2: harder specs
Date: 2026-10-28
Status: done

## Goal
Batch 1 (step 0023) hit the ceiling (8/8 in both languages). Batch 2 uses harder specs with
more edge cases, so correctness could differ between GPLM and Python.

## Specs (`evals/specs/`)
- **calc**: integer expression evaluator per line (precedence, unary minus, truncating `/` `%`,
  1-based syntax-error column, division by zero, deep nesting). 5 cases.
- **csvsum**: RFC-4180-style CSV (quoted fields, `""`, newlines in quotes), group-by + sum,
  record-numbered errors, re-quoting of output keys. 11 cases.
- **inventory**: stateful stock commands (add/remove/move/report/total), strict
  validation, line-numbered errors, sorted report. 5 cases.
- **jsonfmt**: full JSON validator and pretty-printer with exact error line/col, `\u` escape
  normalisation, number grammar, deep nesting (big case). 25 cases.

## Results (8 fresh agents, Claude Opus 5.5, same protocol as batch 1)
| spec | arm | total tokens¹ | time s | lines | chars | fix rounds | hidden |
|---|---|---:|---:|---:|---:|---:|---:|
| calc | GPLM | 57,085 | 47.5 | 209 | 5,364 | 0 | 5/5 |
| calc | Python | 49,828 | 23.5 | 204 | 5,220 | 0 | 5/5 |
| csvsum | GPLM | 62,201 | 91.8 | 239 | 7,326 | 0 | 11/11 |
| csvsum | Python | 50,905 | 33.5 | 180 | 5,081 | 0 | 11/11 |
| inventory | GPLM | 57,599 | 51.8 | 195 | 6,858 | 0 | 5/5 |
| inventory | Python | 50,240 | 27.6 | 166 | 4,988 | 0 | 5/5 |
| jsonfmt | GPLM | n/a² | n/a² | 306 | 8,641 | 0 | 25/25 |
| jsonfmt | Python | 53,457 | 52.1 | 286 | 7,611 | 0 | 25/25 |

¹ includes the prompt (the GPLM prompt carries LANGUAGE.md, ~6k tokens).
² the agent hit a usage limit after handing back its program; usage was not reported.
Candidates: `evals/runs/2026-10-28-batch2/`. Agent transcripts were lost when the session
scratchpad moved, so programs were recovered from the agents' hand-back messages.

## Reading the result
- **Correctness: again a tie at the ceiling.** 8/8 solved first try, 0 checker errors,
  0 fix rounds, all 46 hidden cases per arm. Harder specs of this size (~200–300 lines) still do
  not separate the languages for this model — the theory's correctness claim stays unconfirmed
  and unrefuted.
- **Cost: same picture as batch 1.** GPLM ~2.3x wall time (191 s vs 85 s on the three measured
  specs), ~1.23x program size in characters (28.2k vs 22.9k), +17% total tokens.
  csvsum is the worst (2.7x time, 1.44x chars): byte-level scanning without loops or indexing
  syntax is verbose.
- GPLM programs again type-checked on the first `check`; no operator/loop "false friends".

## Next
- Correctness differences need a different regime: larger multi-file programs, modifying an
  existing codebase, or weaker/cheaper models where error rates are non-zero.
- The cost gap is consistent across 8 specs; shortening GPLM (range loops/iteration helpers,
  string building, byte scanning helpers) is now well-motivated.
