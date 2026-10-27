# Step 0006 — Blind usability test: todo-cli
Date: 2026-10-27
Status: done (app tests pass, `make test` 37/37, `make e2e` passes; no core changes)

## Goal
Find out whether an LLM that has only `core/LANGUAGE.md` can write a working GPLM app,
and record every error it hits. Proposed as next step 1 in STATUS.md after 0005.

## Setup
- The tester agent read only `core/LANGUAGE.md` (116 lines). It did not read `core/*.go`,
  `apps/` or `libs/` sources before or while writing. It did see `.dev/README.md`
  and `.dev/STATUS.md` (index and status, no GPLM code).
- **Caveat:** the tester is the same model family as the agent that designed GPLM, so
  it may share the designer's priors (naming, idioms). This is weaker than a test with
  a different model. It is still a fair test of whether LANGUAGE.md is *sufficient*.
- Task: `apps/todo-cli/main.gp`, a line-based todo manager on stdin
  (`add <text>`, `done <n>`, `list`, `quit`), pure command→state logic with tests,
  io loop in `main`.

## Result: 0 fix rounds
The first version written passed `kaizo check --json` (`[]`), all 5 tests and a manual
`kaizo run` session. **No diagnostic or runtime error was hit while writing the app**,
so there is nothing to log verbatim for the app itself.

Design the tester chose without guidance (all worked first time):
`type Cmd = Add(String) | Done(Int) | List | Quit | Empty | Bad(String) end`,
`step(State, Cmd) -> Outcome { state, out: List[String] }`, `parse(String) -> Cmd`,
`run_lines` (pure, used by tests to drive whole scripts), tail-recursive `loop` with
`read_line()` in `main`. Effects (`! [io]`) were placed correctly on the 3 io fns.

Session transcript:
```
$ printf 'add buy milk\nadd walk dog\nlist\ndone 1\nlist\ndone 9\nfoo\nquit\nadd never\n' | kaizo run apps/todo-cli/main.gp
added 1
added 2
1. [ ] buy milk
2. [ ] walk dog
done 1
1. [x] buy milk
2. [ ] walk dog
error: no such item: 9
error: unknown command: foo
bye
```
Also checked: EOF without `quit` ends cleanly; CRLF input and a missing final newline
work (`read_line` strips `\r\n`).

Because zero rounds gives little signal, the tester then made **deliberate mistakes**
in scratch copies of the app (not in the repo) — the mistakes a fresh writer most
plausibly makes — to see where each one is reported.

## Checker vs runtime (11 injected mistakes + 3 extra probes)

| # | Mistake | Caught by | Message (verbatim) |
|---|---------|-----------|--------------------|
| 1 | `println` in fn without `! [io]` | check | `print_all calls println, which has effect io, but print_all does not declare it` + hint `add io to the effect list of print_all: ! [io]` |
| 2 | drop a `case` of `Cmd` | check | `match is not exhaustive: Bad(_) is not covered` + hint |
| 3 | `if` without `else` | check (parse) | `expected "else" (if is an expression, else is required), found "end"` |
| 4 | `n + 1` | check (lex) | `unexpected character '+'` + hint `GPLM has no operators; use calls like add(a, b), ...` |
| 5 | record literal missing a field | check | `record Todo is missing field(s) done` + hint `every field must be given` |
| 6 | user fn called with 3 args instead of 2 | check | `reply expects 2 arguments, got 3` |
| 7 | invented builtin `list_append` | check | `unknown name list_append` (no "did you mean list_push") |
| 8 | `Some(t, u)` pattern | check | `constructor Some has 1 arguments, pattern gives 2` |
| 9 | `t.txt` instead of `t.text` | **runtime** | `runtime error: record Todo has no field txt` + call stack |
| 10 | `str_cat("added ", list_len(items))` (forgot `show`) | **runtime** | `runtime error: str_cat: argument 2 must be String, got Int` + call stack |
| 11 | fn declared `-> String` returns `str_len(s)` (Int) | **runtime, far away** | first visible symptom: `expect_eq failed  got: Add(12)  expected: Add("buy milk")` in a test; elsewhere `str_cat: argument 2 must be String, got Int` two calls later. The wrong return value is not detected at the fn boundary. |
| P1 | `println` inside an inline lambda in a pure fn | check | `shout calls println, which has effect io, but shout does not declare it` (good: inline lambdas *are* tracked) |
| P2 | local `let` lambda calling itself | check | `unknown name count` (no hint, though LANGUAGE.md lists this gap) |
| P3 | record pattern `case P { x: 1 } ->` | check (parse) | `expected "->" after case pattern, found "{"` (record patterns don't exist; message doesn't say so) |

Summary: 8/11 injected mistakes are caught statically with file:line:col, most with a
fix hint. The 3 that reach run time are exactly the "no static types" gap: wrong field
name, wrong argument type, wrong return type. All 3 were caught by the app's own tests,
so the test-first style compensates — but #11 surfaces far from its cause.

`kaizo test` exits 1 when there are check errors or failed tests (verified).

## Performance finding
Stress test with N `add` lines, then `done 3` and `list` (output correct at every size):

| N | time | max RSS |
|---|------|---------|
| 2 000 | 0.10 s | 15 MB |
| 8 000 | 1.1 s | 16 MB |
| 32 000 | 17 s | 36 MB |
| 200 000 | killed after 130 s at ~144 000 | — |

Quadratic: `list_push` (and `list_concat` in `run_lines`) copies the list each call.
The natural accumulator idiom (`render_all(..., list_push(acc, x))`, state grows by
`list_push`) is O(n²). LANGUAGE.md says nothing about costs, so the writer can't know
to prefer `list_cons` + `list_reverse`. Stack depth was never a problem (tail calls work).

## What was hard
Little. The things the tester had to *guess* (all guessed right, but only by luck or by
choosing a defensive style):
- Can a constructor be called `List` when `List[T]` is a type? (Yes.)
- May `let` shadow? (Yes — the tester avoided it with `acc2` until probing.)
- Does `read_line` include the newline / `\r`? (Strips both; tester used `str_trim` anyway.)
- What do `str_slice` / `list_slice` / `list_get` do out of range? (Slices clamp silently:
  `str_slice("abc", 2, 10) = "c"`; `list_get(l, -1) = None`. Tester guarded with `lt(n, 1)`.)
- May an expression span lines (list literal across lines in a test)? (Yes.)
- How to exit with a non-zero status from `main`? (Not documented; not needed here.)
- Nested `str_cat(a, str_cat(b, str_cat(c, d)))` is the most tedious part of the code;
  `str_join([..], "")` would have been shorter but isn't obviously "the idiom".

## Docs gaps in LANGUAGE.md
1. Out-of-range behaviour of `str_slice`, `list_slice`, `list_get` (negative index).
2. Cost model: `list_push`/`list_concat` are O(n); recommend `list_cons` + `list_reverse`.
3. `read_line` strips `\n` and `\r\n`; returns `None` at EOF.
4. `let` shadowing is allowed (say so, or forbid it).
5. Constructors may reuse builtin type names (`List`, `Option`?) — state the rule.
6. Effects inside an *inline* lambda are attributed to the enclosing fn (only effects of
   function *values* passed in are untracked). The "Known gaps" line reads broader than it is.
7. No record patterns in `match`; access fields with `.` after binding.
8. `kaizo test` exit code and output format; what `expect_eq` prints on failure.
9. How a program exits with a status code (or that it can't).
10. Multi-line expressions are fine (newlines are whitespace inside `( )` / `[ ]`).

## Proposals for the language / core (not implemented in this step)
1. **Check return types and field names cheaply before full typing.** Even without
   inference, `t.txt` where `t: Todo` is a declared param is statically knowable, and
   the interpreter could check a fn's declared return type at return time (runtime
   error at the fn, not two calls later). Covers mistakes #9 and #11.
2. **Arg-type checks for builtins with literal/declared args** (`str_cat(_, list_len(..))`
   is known Int). This is the cheapest slice of the planned static checker (#10).
3. **"Did you mean" hints** for unknown names (edit distance over builtins + module
   names): `list_append` → `list_push`. LLMs invent plausible names.
4. **Hint for local self-recursion**: `unknown name count` → hint "a local let lambda
   cannot call itself; make it a top-level fn".
5. **Hint for record patterns**: on `{` after a constructor name in a pattern, say
   "record patterns are not supported; bind the value and use `.field`".
6. **Persistent list / vector** (or at least O(1) amortized `list_push`), since
   append-accumulate is the idiom LLMs reach for first.
7. **String building**: a variadic-ish `str_concat(list)` or doc that `str_join(l, "")`
   is the idiom, to avoid 4-deep `str_cat` nests.
8. Add the 10 doc gaps above to LANGUAGE.md (cheap, highest value per token).

## What was done
- `apps/todo-cli/main.gp` — 1 file, 5 tests (parse, add+list, done, errors keep state,
  quit stops processing).
- `Makefile` — `make test` now includes `apps/todo-cli/main.gp` (37 tests).
- No changes to `core/` or `specs.md`.

## How to verify
```
make test                                  # 37 passed
build/kaizo test apps/todo-cli/main.gp     # 5 passed
printf 'add a\nadd b\ndone 2\nlist\nquit\n' | build/kaizo run apps/todo-cli/main.gp
```

## Open questions
- Should the next blind test use a *different* model (or a smaller one) to remove the
  shared-priors caveat?
- Is O(n²) list append acceptable for v0, or does it block test project 2b?

## Next step
Human picks. Candidates: (a) apply doc gaps 1–10 to LANGUAGE.md + hints 3–5 (small,
cheap); (b) static checker slice for field names / return types (proposals 1–2);
(c) re-run the blind test with a different model and a harder spec.
