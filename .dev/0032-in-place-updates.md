# Step 0032 — In-place updates of uniquely owned lists
Date: 2026-10-28
Status: done

## Why
After step 0031 the remaining CPU gap came from missing mutable buffers (render3d scanned every
span per pixel; game searched/copied lists). Reference counting already knows when a value is not
shared, so an immutable `list_set` can update in place in that case (Perceus/FBIP, as in Koka/Lean)
— array performance without changing the language's immutable semantics.

## Changes
- Builtins: `list_set(l, i, x)` (in place, O(1), when l has count 1 and is not a view; otherwise a
  copy; out of range returns l unchanged), `list_fill(n, x)`, `list_get_or(l, i, d)` (no Option).
  The parser rewrites `unwrap_or(list_get(l, i), d)` to `list_get_or`, so existing code benefits.
- Codegen: `list_get_or` and the fast path of `list_set` are inline machine code (bounds check,
  load/store, count updates); the slow path calls rt.list_set. Intrinsics `prim_unique`,
  `prim_swap_slot` (store, return the old value), `prim_fill` (native fill with count updates).
- `{ r with ... }` already reused a record with count 1 (no change needed).
- LANGUAGE.md: the three builtins and the rule "pass a list on as its last use; a list read from a
  record field is shared with the record, so list_set on it copies".
- Benchmarks rewritten to the same data structures as C (ring buffer + grid, framebuffer); the
  list-only GPLM versions are kept as game_lists.gp / render3d_spans.gp.
- selftest "list_set, list_fill, list_get_or" (sharing semantics: the original is never changed).
  Seed refreshed (stage-2 fixpoint); full suite, 22 type-error programs, 13 e2e pass.

## Results (bench/run.sh)
| app | 0030 | 0031 | 0032 | C | GPLM/C |
|---|---:|---:|---:|---:|---|
| game (2M ticks) | 6.55 s | 1.44 s | 0.46 s | 0.028 s | 243x → 16.5x |
| render3d (2000 frames) | 7.51 s | 7.66 s | 2.02 s | 0.448 s | 17x → 4.5x |
| server | 0.77x | 0.75x | 0.82x | | I/O bound |
Memory stays below C/Rust (0.4–0.8 MB RSS).

## What is left (profiles)
render3d: 54% in the per-pixel checksum loop, 18% in the span fill — plain Int arithmetic and
loop overhead: tag checks on every operation, `mod` via idiv with tag fix-ups, arguments in stack
slots, tail calls through memory. game: allocations of small candidate lists (list_concat) and
call overhead. Next: codegen — drop Int tag checks the type checker proves, keep loop variables in
registers, cheaper tail calls.
