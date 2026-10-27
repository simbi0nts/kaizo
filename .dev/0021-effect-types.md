# Step 0021 — Function types carry effects (the handler gap is closed)
Date: 2026-10-27
Status: done

## Goal
Until now effects were checked only for direct calls. A function passed around as a value — an
HTTP handler, a callback — could print or use the network without anyone declaring it.

## Design
- Syntax: `Fn(A) -> B ! [io, net]` in any type position (parameters, record fields, type args).
  `Fn(A) -> B` is pure.
- Type checker: function types are `TF(params, result, effects)`. A function value fits where a
  function type is expected only if its effects are a subset of the allowed ones. Calling any
  function value uses its effects; a lambda's effects are inferred from its body.
- Builtins with function arguments (`list_map`, `list_filter`, `list_fold`, `list_sort_by`) are
  effect-transparent: the effects of the function given to them count for the caller.
- At the end of each function, effects used through function values must be declared (direct
  calls were already checked earlier by check.gp). Top-level lets must stay pure.
- Builtin signatures (`core/rt/types.gp`) now state their effects.

## Verification
- 5 new wrong programs in `tests/type_errors/` (16 total): an HTTP handler lambda that prints,
  a named handler declared `! [io]` passed to `http.serve` (whose handler type is pure), calling an
  effectful function parameter without declaring the effect, a stored lambda using `net`, a
  printing lambda inside `list_map` in a pure function.
- All existing code needed **no changes**: every callback in the code base was already used
  consistently with its effects.
- `make all` (13 suites), selfhost fixpoint, e2e 13, gui 8.

## Next
0022 — use the types: reference counting can skip values known to be Int; docs.
