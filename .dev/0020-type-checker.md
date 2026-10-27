# Step 0020 — Static type checker (inference, generics, records)
Date: 2026-10-27
Status: done

## Goal
Phase 1 of ROADMAP.md: errors that LLMs make should be caught before run time. Until now
wrong-typed arguments, wrong field names and wrong return types reached run time.

## Design (core/typecheck.gp, ~550 lines; builtin signatures core/rt/types.gp)
- Unification with type variables (Hindley-Milner style), no let-generalisation for locals.
- Annotations: only the existing ones (top-level signatures, type declarations). Single capital
  letters in a signature are type variables unless a type of that name exists; they are **rigid**
  inside the body and **fresh** at every use.
- Bidirectional where it matters: arguments are checked against the callee's parameter types, so
  lambda parameters get their types from the call (`list_map(ps, fn(p) p.name end)`).
- Field access on a value whose record type is not known yet: resolved later in the function; if
  only one record type has the field, that one is used; otherwise a clear "annotate" error.
- Builtin types are written as GPLM signatures (`core/rt/types.gp`) and parsed by kaizo's own parser.
- The runtime module is not type-checked (it works below the type system with prim_*).
- Runs after the existing checks; diagnostics have the usual format (and --json).

## What the checker found in existing code
| Where | Finding | Fix |
|---|---|---|
| core/codegen.gp | 3 signatures still said `List[Int]` after the IR refactor (step 0011) — 133 errors from them | annotations corrected |
| libs/x11 + both GUI apps | tests built a fake connection `X { sock: Unit, ... }` — a type lie that ran fine dynamically | drawing now takes a `Draw { win, gc }` context; tests need no socket |
| everything else (13 suites, compiler) | type-correct as written | — |
False alarm during development: record types named with one letter (`P`, `X`) were taken for type
variables — fixed (a declared type name is never a variable).

## Verification
- `tests/type_errors/` — 11 wrong programs, each must produce its expected message (field typo,
  argument type, return type, pattern type, if branches, lambda result, comparison of different
  types, constructor argument, record field, rigid generic, function type). Part of `make test`.
  Includes the three mistake kinds that reached run time in the blind test (step 0006).
- `make all` (13 suites), `make selfhost` (fixpoint), e2e 13, gui 8, cross builds checked.
- Cost: `kaizo check core` 0.17 s → 0.22 s.

## Next
0021 — effects in function types (closes the handler gap: a function value's effects are checked).
