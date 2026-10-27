# Step 0001 — Concept proposal: core, language, test projects
Date: 2026-10-27
Status: proposal (waiting for human decisions, see "Open questions")

## Goal
Turn "Theory 1" from specs.md into concrete, buildable decisions, small enough
that step 0002 can produce a running core.

## 1. Architecture (Theory 1, made concrete)

| Part | Proposal |
|------|----------|
| Core | One static binary `kaizo`: parser, type checker, interpreter, test runner, builder. Subcommands: `run`, `check`, `test`, `build`. |
| Libraries | `libs/<name>/*.gp`, pure GPLM source. Imported by name; a lockfile pins each import by **content hash** of its code, so libraries shared between agents can't silently change under an app. |
| App | `kaizo build app.gp -o app` = copy of the core binary + compiled app bytecode appended to it. A real standalone executable with no codegen backend needed. Native codegen can come much later without changing apps. |

The core keeps only what can't be written in GPLM: data types, control flow,
and primitive effects (stdout/stdin, terminal raw mode, clock/sleep, random,
files, TCP sockets). Everything else (HTTP, JSON, HTML, game helpers) goes in libs.

## 2. Language principles: what "for an LLM" means

Kept (functional features that reduce LLM mistakes or make them visible):
1. **One way to write each thing.** No synonyms, no optional syntax, no operator
   precedence (calls only: `add(a, mul(b, c))`). Fewer choices, fewer mistakes.
2. **Explicitly closed blocks** (`fn ... end`), whitespace not significant.
   Truncated or garbled output is a parse error, never a silent change in meaning.
3. **Static types; signatures required on top-level functions**, inferred
   inside. A function can be checked using only its signature.
4. **Immutable values, ADTs + exhaustive `match`.** The checker rejects a
   forgotten case.
5. **No exceptions.** Errors are `Result` values; panics only for real bugs.
6. **Effects in the signature** (`fn tick() -> Unit ! [term, time]`). A pure
   function can't do IO; this is checked. Pure code is safe to test and reuse.
7. **Tests and examples are syntax, not convention** (`test "name" ... end` next
   to the code). This replaces human code review: specs → tests → code.
8. **Machine-first diagnostics.** `kaizo check --json` gives errors with exact
   spans and a suggested fix, for the agent's repair loop.
9. **Content-addressed definitions** (idea from Unison): identity = hash of
   code, so renames and moves don't break anything, and caching/sharing is trivial.

Dropped as "developer comfort": operator overloading, implicit conversions,
macros, inheritance, multiple syntaxes, significant indentation, nulls.

Sketch (syntax is a proposal, not final):
```
type Dir = Up | Down | Left | Right end
type Snake = { body: List[Pos], dir: Dir } end

fn turn(s: Snake, d: Dir) -> Snake
  match pair(s.dir, d)
    (Up, Down) | (Down, Up) | (Left, Right) | (Right, Left) -> s
    _ -> { s with dir: d }
  end
end

test "reverse is ignored"
  expect_eq(turn(snake_right(), Left).dir, Right)
end
```

## 3. Test project 2: no browser needed
"Test page in browser" doesn't need us to build a browser. Proposal:
- **2a (main):** the GPLM app is a tiny HTTP server serving Hello World; you open
  it in your normal browser. HTTP parsing is a GPLM library (`libs/http`), so
  this test also proves the library part of Theory 1.
- **2b (stretch, later):** a mini *text* browser in GPLM that fetches that page
  and renders h1/p/a to the terminal. Realistic (~few hundred lines), reuses
  `libs/http`, so it's the first real case of sharing a library.
- A full graphical browser is out of scope for the concept test.

Acceptance criteria: `apps/snake/ACCEPTANCE.md`, `apps/hello-web/ACCEPTANCE.md`.

## 4. Host language for the core (recommendation: Go)
| Option | + | − |
|--------|---|---|
| **Go** (recommended) | static single binary by default, cross-compiles, GC (no memory bugs in interpreter), TCP/terminal in stdlib | bigger binary (~3–5 MB) |
| C | tiny binary, max portability | memory-safety bugs in the interpreter, more code for sockets/terminal |
| Rust | safe + fast | not installed here; slower to iterate |

Go 1.26 is installed. Only the core is in Go; apps and libs are pure GPLM.
A self-hosted core (GPLM written in GPLM) is a possible far-future step.

## 5. Roadmap (each item = one or more steps)
1. 0002 Core skeleton: lexer, parser, tree-walking evaluator; `print`; `kaizo run`.
2. Types: records, ADTs, `match`, lists, checker with exhaustiveness.
3. Effects + `test` blocks + `kaizo test`; `--json` diagnostics.
4. Primitive effects: terminal, time, random → **Snake** (test 1).
5. `kaizo build` (binary + appended bytecode).
6. Sockets + `libs/http` → **Hello web** (test 2a).
7. Imports, content hashes, lockfile → **mini text browser** (test 2b).

## Open questions (human decision)
1. Host language for the core: Go (recommended) / C / other?
2. Syntax family: keyword blocks (`fn … end`, sketched above) or S-expressions
   (simplest to parse, but LLMs miscount parens in long code)?
3. Agree that test 2 = server + your existing browser, with mini browser as 2b?
4. File extension `.gp`, CLI name `kaizo`: OK?

## Next step
0002 — core skeleton (after the answers above).
