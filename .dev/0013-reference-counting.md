# Step 0013 — Compiler-inferred reference counting (memory is freed)
Date: 2026-10-27
Status: done

## Goal
Programs (servers above all) must not grow without bound. Human chose compiler-inferred reference
counting over a tracing GC and over Rust-style borrowing visible in the language (see the discussion
before this step): GPLM values are immutable and closures cannot refer to themselves, so the heap is
acyclic and counting alone reclaims everything — with nothing for the programmer to write.

## Design
- `core/rc.gp`: backward liveness per function (Perceus-style). A use is a **move** if it is the
  last one, otherwise a **dup**. Drops: unused parameters at entry, dead lets right after the let,
  variables used only on other branches at branch/arm entry, pattern variables are dup'ed on a match
  only if the arm uses them. **Borrowed** uses (field access, match on a variable, read-only intrinsics)
  cost nothing; if that was the last use the variable is dropped at the end of the statement
  (before a tail jump if the statement ends in one).
- Object layout: a count word before every object (static objects: immortal count). Lists are
  `[header][data][owner][elements]`; a list view (`[x, ..rest]`, list_slice...) keeps its owner alive.
- Memory: `rt_alloc` / `rt_free` / `rt_class` (gen.gp): size-class free lists (8-byte steps up to
  1 KiB, powers of two above), freeing is recursive, freed headers are poisoned (0xEE).
- Record update `{ r with ... }` evaluates the new field values first and **reuses the record in
  place** when its count is 1.
- Lambdas own their closure for the duration of the call (dropped on return / before a tail jump).
- New IR ops: IAddM, IDecM, IZeroQ, IRet. Debug aids: `rc_debug` in codegen.gp (never reuse freed
  blocks + trap on counting a freed object) and `kaizo build ... --map` (symbol map for gdb).

## The one bug found
Self-compile crashed: a temporary created inside an `elif` condition was dropped at the end of the
statement even on paths where the condition never ran (stale slot). Found with rc_debug + --map + gdb
in a few minutes; fixed by initialising temporary slots to Int 0 at function entry.

## Results
| | before (bump allocator, no freeing) | after |
|---|---|---|
| compiler compiling itself, peak RSS | 432 MB | **67 MB** |
| compiler compiling itself, time | 0.50 s | 0.88 s (allocator calls + count traffic; not optimised yet) |
| hello-web RSS after 200 → 2200 requests | 1.5 MB → 15.2 MB (grows ~7 KB/request) | **184 KB → 184 KB** |
| all suites, core tests (51), fixpoint, Snake pty e2e, cross builds (PE, Mach-O x2 verified) | | pass |

## Next
Speed: inline the common allocation path, skip count traffic for values known to be Int (needs the
type checker), reuse for `list_push`/`list_cons` when the list is unique.
