# Step 0031 — Performance: profiler and runtime quick wins
Date: 2026-10-28
Status: done

## Profiler
`tools/kprof.py <binary> [args]`: sampling profiler without perf (perf_event_paranoid=4 here) —
ptrace stops the program every ~1 ms, reads rip, maps it with the `--map` file that
`kaizo build ... --map` already writes. Usage: `kaizo build app.gp -o app --map && tools/kprof.py app`.

## Findings (profiles of the step-0030 benchmarks)
| benchmark | hotspot | share | cause |
|---|---|---:|---|
| game | rt.equal + slots_eq + contains_loop + same | ~60% | generic deep `==` (tag dispatch, RC dup/drop per field, a call per field) |
| game | rt.copy_into | 18% | list_slice copied element by element (view existed but was copied) |
| render3d | main.pixel | 38% | no mutable buffer: every pixel scans the row's spans |
| render3d | rt_alloc + rt_free | 30% | a heap object per record / Option / intermediate list |
Micro-benchmarks vs C: Int tail loop 2.2x, list_get ~10x (Option allocation), record alloc
~14 ns, fold ~6 ns/element, fib(32) 0.02 s — the core codegen is not the main problem.

## Changes (runtime + 4 intrinsics, no language change)
- `prim_eq_flat(a, b)`: machine-code comparison of two values: identical words → equal; differing
  words with an Int → not equal; records/constructors of the same type compared word by word
  without RC traffic; only nested pointers fall back to the deep comparison (`equal_deep`).
- `prim_find_flat(l, x, i, n)`: list scan with the same comparison (list_contains).
- `prim_copy_slots(dst, doff, src, soff, n)`: bulk slot copy with inline count increments
  (list_cons/push/concat/... via copy_into).
- `prim_slot_cmp`: raw slot comparison used by slots_eq.
- `list_slice` returns the existing O(1) view instead of a copy.
Seed refreshed (stage-2 fixpoint); full suite, 22 type-error programs, 13 e2e pass.

## Results (bench/run.sh)
| app | before (0030) | after | C | GPLM/C before → after |
|---|---:|---:|---:|---|
| game (2M ticks) | 6.55 s | 1.44 s | 0.027 s | 243x → 53x (vs C with same data structures: 56x → 12x) |
| render3d (2000 frames) | 7.51 s | 7.66 s | 0.45 s | 17x → 17x (bound by missing arrays + allocation) |
| server | 77k req/s | 73k req/s | 93–104k | ~0.75x (I/O bound, unchanged) |
The compiler builds itself in 1.3 s.

## Next (in order of expected effect)
1. In-place update of uniquely owned values (count == 1): `list_set`, `list_push`, `{ r with }`
   reuse the object instead of copying (Perceus/FBIP as in Koka/Lean) — gives array-speed
   framebuffers and grids with the immutable API; render3d's per-pixel scan becomes a buffer write.
2. Allocation: reuse a just-freed block for the next same-size allocation (drop+alloc pairs in
   `{ g with }` / constructors), inline rt_class for small sizes, no Option allocation in hot
   list_get paths.
3. Codegen: skip `need` checks proven by the type checker, inline small rt functions, registers.
