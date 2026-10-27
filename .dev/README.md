# .dev — development log of Project Kaizo (GPLM)

Every development step is one file `NNNN-<slug>.md` plus one (or more) git commits
whose message starts with `[step NNNN]`. Steps are append-only: a later step may
revise an earlier decision, but it says so explicitly instead of editing history.

`specs.md` (repo root) is owned by the human and is never edited by agents.

## How to resume on another machine

1. `git clone <repo>` and read, in order: `specs.md`, this file, `STATUS.md`.
2. Read the newest step file; it ends with "Next step".
3. Install the toolchain listed in `STATUS.md` → "Toolchain".
4. Continue with the next step number.

## Step file template

```
# Step NNNN — <title>
Date: YYYY-MM-DD
Status: done | in progress | proposal (waiting for human decision)

## Goal
## Decisions (with reasons)
## What was done
## How to verify
## Open questions
## Next step
```

## Index

| Step | Title | Status |
|------|-------|--------|
| [0000](0000-bootstrap.md) | Repository bootstrap | done |
| [0001](0001-concept-proposal.md) | Concept proposal: core, language, test projects | accepted in 0002 |
| [0002](0002-decisions.md) | Answers to the open questions | done |
| [0003](0003-core-v0.md) | Core v0: interpreter, checker, run/check/test/build | done |
| [0004](0004-snake.md) | Test project 1: Snake | done |
| [0005](0005-hello-web.md) | Test project 2a: Hello web | done |
| 0006 | Blind usability test (on branch claude/nifty-edison-01274c) | done, not merged |
| [0007](0007-self-hosting-plan.md) | Plan: self-hosted native GPLM, Go only for bootstrap | done |
| [0008](0008-front-end.md) | Compiler front end in GPLM | done |
