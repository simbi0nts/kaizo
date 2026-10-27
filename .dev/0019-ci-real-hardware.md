# Step 0019 — CI on real Windows and macOS: two bugs found and fixed, all targets green
Date: 2026-10-27
Status: done

## Goal
Finish Phase 0: run the CI from step 0011 on real runners (repository github.com/simbi0nts/kaizo).

## What happened
| Run | Linux | Windows x64 | macOS arm64 | macOS x86-64 |
|---|---|---|---|---|
| #1–#3 | pass | suites pass; cross-host fixpoint fails | segfault at start-up | **pass** (first try) |
| #4 (777212a) | pass | **pass** | **pass** | pass |

1. **arm64 start-up crash.** `rt_alloc` had no frame but called `rt_class`. On x86 `call` keeps the
   return address on the stack; on arm64 `bl` writes it to x30, so the inner call overwrote
   rt_alloc's own return address and the first allocation returned into nowhere. Fix: rt_alloc
   gets a frame (IEnter/ILeave). Found by reasoning about the arm64 calling convention from the
   crash pattern (every command, immediately; Intel Macs fine).
2. **Windows fixpoint.** Git on Windows checked sources out with CRLF; the runtime sources are
   embedded into kaizo, so its output differed. Fix: `.gitattributes` (`* text=auto eol=lf`).
- CI plumbing: step logs need sign-in even on public repos; check output is now also published as
  a public annotation (readable through the API) plus an lldb backtrace if kaizo crashes.

## Result (run #4)
On every OS the native kaizo runs, passes all 13 suites, rebuilds itself **for all four targets
byte-identically to the Linux cross builds**, serves hello-web over HTTP; Snake's terminal test
passes 7/7 on both Macs (pty), Windows reports the missing console correctly.

## Still unverified
Interactive console Snake on Windows (no console on the runner); GUI apps (X11 only).

## Next
Phase 1 — static type checker (renumbered: starts at 0020).
