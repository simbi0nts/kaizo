# Step 0013 — Compiler-inferred reference counting (IN PROGRESS, on branch wip/rc-step-0013)
Date: 2026-10-27
Status: in progress — not merged; main and seed/kaizo are unchanged.

## Design (implemented)
Perceus-style: `core/rc.gp` liveness pass (move on last use, dup otherwise; drops at function
entry, after dead lets, at branch/arm entries; borrowed uses for field access, match scrutinee and
read-only intrinsics with drops at statement end). Count word before every object (static objects
immortal). Lists: [header][data][owner][elements]; views keep their owner alive. Allocator with
size-class free lists (`rt_alloc`, `rt_class`, `rt_free` in gen.gp). Record update reuses the
record in place when its count is 1. New IR ops IAddM/IDecM/IZeroQ/IRet. `kaizo build --map`.

## Results so far
- Programs compiled by the RC compiler: all 7 suites pass; hello works.
- Self-compile peak memory with RC on the failing run: 11 MB (vs 427 MB without RC) — not yet valid.
- BUG: the RC-compiled compiler (`kaizo-rc2`) segfaults building hello-web/snake: free-list head
  corrupted in rt_alloc (`mov (%rcx),%rax` with garbage rcx) => a freed block is written to later
  (use-after-free: a dup/drop on an already freed object). snake: "no case matched value <handle>"
  in map.get = poisoned (0xEE) header read.

## Next
Find the premature free: reproduce with `build/kaizo-rc2 build apps/hello-web/main.gp`, use
`--map` + gdb; suspects: borrowed temps dropped at statement end while a moved alias lives on,
tail-call drops, record-update reuse, list views. Add a debug mode that never reuses freed blocks.
