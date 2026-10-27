# Step 0008 — Compiler front end in GPLM
Date: 2026-10-27
Status: done

## Goal
Lexer, parser, module loader and checker written in GPLM (`core/*.gp`), producing the same
diagnostics as the Go v0 core.

## What was done
- `core/ast.gp` AST as ADTs/records · `core/lexer.gp` (tokens in a linked-list ADT so appends
  are O(1) in both the Go interpreter and native code) · `core/parser.gp` (functional:
  state threaded through every call; first error is recorded and the token stream is cut so
  all loops unwind) · `core/program.gp` (reading files, `libs/` search, linking types/ctors,
  dependency order, builtin + intrinsic tables) · `core/check.gp` (names, arity, record
  fields, types, exhaustiveness with witness, effects) · `core/main.gp` (`check [--json]`).
- Restructure: `core/` now only holds compiler sources; `core/rt/prelude.gp` (embedded with
  `embed_file`), `tests/selftest.gp`.

## Verification
- Parser errors for 6 malformed files are byte-identical to the Go parser's.
- Checker output on the 7-error sample (`bad.gp` from step 0003) is identical to Go's.
- All existing programs check `ok`, including the compiler itself (`kaizo-go run core check core`, 2.2 s).
- Found by the Go checker while writing: my parser helper named `expect` clashed with the
  builtin; and GPLM has no anonymous records (`{ c: x }` must be `Seen { c: x }`) — both
  caught statically.

## Next step
0009 — back end: x86-64 encoder, ELF writer, runtime `core/rt/rt.gp`, codegen.
