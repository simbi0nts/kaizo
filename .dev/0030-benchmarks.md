# Step 0030 — Performance benchmarks vs C and Rust
Date: 2026-10-28
Status: done

## What was built (`bench/`)
- Three apps with exact specs and byte-identical output in GPLM, C, Rust: `game` (headless Snake,
  deterministic AI), `render3d` (fixed-point rasterizer, 4 spinning cubes, painter's order),
  `server` (HTTP hello server, one thread, Connection: close) + `server/load.c` load generator.
- `bench/run.sh`: builds, verifies outputs, prints the table. `game/game_list.c`: C using GPLM's
  data structures (copied list, linear search) to separate codegen cost from data-structure cost.
- Rust 1.99.1 installed with rustup (user-approved; ~/.rustup, ~/.cargo).

## Results (Linux x86-64, 14 cores, single-threaded programs)
| app | metric | C | Rust | GPLM | GPLM/C | GPLM/Rust |
|---|---|---:|---:|---:|---:|---:|
| game (2M ticks) | time s | 0.027 | 0.031 | 6.551 | 243x | 211x |
| game | max RSS KB | 1808 | 2332 | 392 | | |
| game, C with GPLM data structures | time s | 0.116 | | | 56x | |
| render3d (2000 frames) | time s | 0.447 | 0.425 | 7.513 | 17x | 18x |
| render3d | max RSS KB | 2196 | 2416 | 392 | | |
| server (8 clients, 5 s) | req/s | 100705 | 103979 | 77434 | 0.77x | 0.74x |
| server | p99 ms | 0.217 | 0.213 | 0.218 | | |
| binary size KB | game / render3d / server | 16/15/16 | 4439/4452/4448 | 186/206/170 | | |

## Reading the result
- **I/O-bound work is close**: the server reaches 0.74–0.77x of C/Rust with the same p99; the
  kernel dominates. (libs/http logs every request to stdout; the benchmark discards it.)
- **CPU-bound work is 17–240x slower.** Two causes, separable with game_list.c:
  - *Missing data structures* (≈4x on game): no mutable arrays/maps, so collision tests are linear
    scans and every move copies the body.
  - *Code generation and runtime* (≈56x on game, ≈17x on render3d with array-free code in both):
    likely boxed/tagged values with runtime type checks in builtins (`need`), `list_get` returning
    an allocated Option, reference-counting traffic, closures for list_map/fold, no register
    allocation (stack slots), no inlining. Not profiled: `perf` is not permitted on this machine
    (perf_event_paranoid); the binaries carry no symbols.
- **Memory and size are good**: 0.4 MB RSS (no libc, RC frees immediately) vs ~2 MB; binaries
  ~0.2 MB vs 16 KB (C, dynamic libc) and 4.4 MB (Rust, static std).
- Correctness side finding: GPLM's `div`/`mod` are *floored* (Python semantics), not Euclidean as
  LANGUAGE.md said (they differ for negative divisors); docs fixed. Rust's `div_euclid` was the wrong
  match and gave a different image until replaced by floor division.

## Next (performance track, pulled into T5)
1. Mutable arrays/buffers with ownership-checked in-place update (unique RC → no copy) and a hash map.
2. Unboxed Int fast paths in codegen (skip `need` checks the type checker already proved), inline
   small builtins (add/lt/eq on Int), register allocation for locals.
3. Symbols in binaries (or a `--profile` sampling mode in the runtime) so GPLM code can be profiled.
Re-run bench/run.sh after each; target ≤ 3x C on render3d.
