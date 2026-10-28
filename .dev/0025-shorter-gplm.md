# Step 0025 — Shorter GPLM: try, variadic builtins, read_all
Date: 2026-10-28
Status: done

## Why
Batches 1–2 (steps 0023–0024): GPLM tied Python on correctness but cost ~2.3x the time and
~1.23x the characters. Counting the 8 GPLM candidates showed the main repeated boilerplate:
- ~20 propagation arms `case Err(e) -> Err(e)` / `case None -> None` (each a 4–5 line `match`);
- nested `str_cat(a, str_cat(b, c))` and `or(a, or(b, c))` chains;
- a hand-written stdin loop over `read_line` in 6 of 8 programs.

## What changed (core)
- **`try` statement** (parser desugaring, no new AST node):
  `let x = try e` + rest → `match e case Ok(x) -> rest case Err(err) -> Err(err) end`;
  `let x = try e else alt` (for Option) → `match e case Some(x) -> rest case None -> alt end`;
  bare `try e` ignores the value. It ends the *enclosing block*, so that block must have the
  failure's type; `try` cannot be the last statement. `try` is a keyword now.
  Gotcha found: rc.gp keys arms and statements by source position, so the generated nodes need
  distinct positions (both arms at the `try` keyword corrupted reference counts → runtime error).
- Type-checker hints for the two likely mistakes: `try` on an Option without `else` (or with
  `else` on a Result), and `try` in a block whose type is not a Result.
- **Variadic** `add mul str_cat and or bit_and bit_or bit_xor` (2+ args, right-folded in the parser).
- **`read_all() -> String ! [io]`**: all of stdin in 64 KiB reads (os_read_stdin per OS; on
  Windows a failed ReadFile on a closed pipe counts as the end). The first version collected bytes
  with `list_push` (lists are immutable arrays → quadratic): 277 KB took 4 minutes; now 2 ms.
- Tests: selftest "try" and "variadic builtins"; type_errors try_option/try_block/try_last (19 now);
  ci_platform.sh pipes 300 KB through tests/read_all.gp on every OS. Seed refreshed (fixpoint).
- evals/arms/gplm.md: "Read all of standard input with `read_all()`, or line by line with `read_line()`".

## Measurement: batch 2 specs again, GPLM arm only (batch2b, 4 fresh agents)
| spec | chars before → after (Python) | lines | total tokens¹ | time s |
|---|---|---|---|---|
| calc | 5,364 → 5,176 (5,220) | 209 → 197 | 57,085 → 53,731 | 47.5 → 42.7 |
| csvsum | 7,326 → 6,553 (5,081) | 239 → 211 | 62,201 → 59,800 | 91.8 → 87.7 |
| inventory | 6,858 → 6,334 (4,988) | 195 → 227 | 57,599 → 57,522 | 51.8 → 68.7 |
| jsonfmt | 8,641 → 9,933 (7,611) | 306 → 394 | n/a → 64,223 | n/a → 126.7 |
¹ the prompt grew by ~0.8k tokens (LANGUAGE.md); included.

All 4 solved first try, 0 fix rounds, 46/46 hidden. (csvsum first hit the 'big' timeout because of
the slow read_all above; the unchanged program passed after the runtime fix.)

## Reading the result (honestly)
- **Adoption is complete**: `try` used 24 times in 3 of 4 programs, no propagation arm left;
  variadic calls in all 4; `read_all` in 2. Every program still type-checked on the first try.
- **Size effect is small and noisy**: −7.6% characters on the three specs that had the old
  pattern (calc, csvsum, inventory), but jsonfmt grew +15% because this agent chose a different
  design (a JSON tree + renderer instead of streaming). Over all 4: 28.2k → 28.0k chars vs Python
  22.9k. Time and tokens did not change meaningfully (−3% tokens on the 3 comparable specs).
- With one run per spec, program design varies more than syntax saves. The remaining gap to
  Python is mostly structural: loops over indices (tail-recursive helpers with 4–8 threaded
  parameters), byte scanning with numeric codes, and accumulator plumbing (list_cons + reverse).

## Next
- Repeat runs (≥3 per spec and arm) before claiming size effects of under ~10%.
- Bigger levers for the remaining gap: an iteration form over ranges/strings with an accumulator,
  character literals for bytes, a string builder. Each should be measured the same way.
