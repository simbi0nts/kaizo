# Step 0002 — Answers to the open questions of 0001
Date: 2026-10-27
Status: done

## Goal
Close the open questions of step 0001 so implementation can start.

## Decisions
The human said "any suggestions are acceptable", so the recommendations of 0001 are accepted:

| Question | Decision | Reason |
|----------|----------|--------|
| Host language of the core | **Go** | static single binary, GC (no memory bugs in the interpreter), TCP + terminal in stdlib, installed here |
| Syntax family | **keyword blocks** (`fn … end`, `match … case … end`) | explicit closing, LLMs miscount parens in long S-expressions |
| Test 2 | **2a: GPLM HTTP server + any existing browser**; 2b mini text browser later | writing a graphical browser is not needed to prove the concept |
| Names | file extension `.gp`, CLI `kaizo` | short, unique |

Scope rule for the next steps: **start small**. First a dynamic interpreter with static
*checks* (names, arity, exhaustiveness, effects); a full static type checker is a later step.

## Next step
0003 — core v0: lexer, parser, checker, tree-walking interpreter, `run/check/test/build`.
