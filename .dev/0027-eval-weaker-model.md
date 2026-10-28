# Step 0027 — Correctness with a weaker model (Claude Haiku 5.5)
Date: 2026-10-28
Status: done

## Why
Opus solved every spec first try in both languages (44/44, steps 0023–0026), so the theory's main
claim — GPLM makes LLM programs more correct — could not be tested. A weaker model makes mistakes;
the fix rounds then show whether GPLM's checker leads to correct programs sooner than Python.

## What was done
24 fresh Haiku agents: batch-2 specs (calc, csvsum, inventory, jsonfmt) × 2 arms × 3 runs, same
prompts and protocol as before (≤3 fix rounds, feedback = verbatim diagnostics / failing test).
results.jsonl batch `batch2h` (model claude-haiku-5-5, new field `first_try`); every program
version is in `evals/runs/2026-10-28-batch2h/` (`-f0` first answer, `-f1` after one fix round).

## Results
| arm | first-try solved | solved (≤3 rounds) | fix rounds | chars | total tokens¹ | time |
|---|---:|---:|---:|---:|---:|---:|
| Python | **12/12** | 12/12 | 0 | 1x | 1x | 1x |
| GPLM | **9/12** | 12/12 | 3 | 1.50x | 1.44x | 3.02x |
¹ cumulative over fix rounds; per spec: calc 1.31x, csvsum 1.59x, inventory 1.46x, jsonfmt 1.40x.

The three GPLM failures (all fixed after one round):
1. inventory r1 and r2: `exit(if failed then 1 else 0)` — an inline `if` without `end` (the
   Python `x if c else y` habit). The checker said `expected an expression, found ")"`, which does
   not name the cause; both agents still fixed it in one round.
2. calc r2: C-style truncating division built on GPLM's Euclidean `div`/`mod` with a wrong sign
   correction. Caught by the agent's own unit test (`kaizo test`), not by the type checker.
No Python run failed at any stage. No GPLM error was a type error the checker could have prevented
in Python either.

## Reading the result (honestly)
- **The correctness claim is not supported at this scale; the sign is against GPLM.** With a weaker
  model, GPLM's unfamiliar syntax and semantics *cause* errors (25% of first answers) that Python
  does not have, and the static checker found only errors the language itself introduced.
- **Recovery works**: every failure was fixed in one round from the diagnostics/test output.
- **Cost grows with a weaker model**: 1.50x size and 3.0x time (Opus: 1.26x and 1.97x). The language
  reference costs a weaker model more to apply.
- Small sample (3 runs per spec); but 12/12 vs 9/12 with all failures caused by GPLM-specific
  constructs is a clear direction.

## Changes made from the findings
- Parser: a block that runs into `)`, `,`, `]` or `}` now reports
  `expected end to close the block, found ")"` with the hint
  `exit(if c then 1 else 0 end)` (tests/type_errors/if_missing_end.gp, 20 wrong programs now).
- LANGUAGE.md: `if` needs `end` also inline (with the example); `div(-7, 2) = -4` and how to get
  C-style truncation. Seed refreshed. Not yet re-measured (would need new runs).

## Next
- Re-run the Haiku GPLM arm (≥3 runs) to see whether the diagnostic + reference changes remove
  these failures.
- The theory needs tasks where *Python's* typical errors appear (type confusion, None handling,
  forgotten cases in larger state machines, multi-file changes); the current specs are too small
  for the checker's guarantees (exhaustive match, effects, Result) to matter.
