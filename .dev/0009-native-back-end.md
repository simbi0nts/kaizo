# Step 0009 — Native back end in GPLM; self-hosting fixpoint reached
Date: 2026-10-27
Status: done

## Goal
Compile GPLM straight to x86-64 Linux ELF, with every part written in GPLM.

## What was done
- `core/x64.gp` — instruction encoders (byte lists), code rope, two-pass assembler per
  function (local labels resolved, others become fixups), linker (layout, symbol table,
  rel32/abs32/abs64 patching), ELF64 writer (one RWX PT_LOAD at 0x400000, no sections).
- `core/codegen.gp` — stack-machine code generator: tagged ints, objects with tag headers,
  closures with captured values (lambda lifting via free-variable analysis), callee-pops
  convention, general tail calls (frame rewrite + jmp, direct and indirect), match
  compilation (sequential arms, nested patterns, list rest views), record field access by
  dispatch on type id, dynamic checks with `file:line:col` runtime errors, 20 intrinsics.
- `core/gen.gp` — whole program: functions, static closures, constructor/record descriptor
  tables, `init` for top-level lets, wrappers for builtins/constructors used as values,
  `_start` (64 GiB NORESERVE heap, 1 GiB stack, SIGINT/SIGTERM handler restoring the
  terminal, SIGPIPE ignored), test mode entry.
- `core/rt/rt.gp` — the runtime in GPLM (strings, lists, show/equal/compare, io, terminal,
  time, TCP, files, `run_image` via memfd_create+execveat, test runner forking one child
  per test). Embedded into the compiler with `embed_file`.
- `core/main.gp` — `build`, `run` (compile in memory and exec), `test`.
- Name clashes (`le`, `load`) and anonymous records were again caught by the checker.

## Results
| | |
|---|---|
| Hello world | native ELF, 97 KB, ran correctly on the first attempt |
| Test suites, native | selftest 8, rand 3, http 3, map 2, snake 14, hello-web 4 → **34/34 pass** |
| Failure reporting | expect_eq diff, div by zero, type errors with file:line:col; test runner continues |
| Bootstrap | Go interpreter runs the compiler on itself: 11 s → `kaizo1` (783 KB) |
| Self-compile | `kaizo1 build core` = 0.75 s, max RSS 256 MB (no GC) |
| **Fixpoint** | `kaizo1 == kaizo2 == kaizo3` byte-identical (sha256 f66645f4…) |

Compiler size: ~3.9k lines of GPLM (front end, back end, runtime).

## Next step
0010 — delete the Go bootstrap, commit the seed binary, switch Makefile and docs.
