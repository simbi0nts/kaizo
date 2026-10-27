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

Long-term plan: [ROADMAP.md](ROADMAP.md)

## Index

| Step | Title | Status |
|------|-------|--------|
| [0000](0000-bootstrap.md) | Repository bootstrap | done |
| [0001](0001-concept-proposal.md) | Concept proposal: core, language, test projects | accepted in 0002 |
| [0002](0002-decisions.md) | Answers to the open questions | done |
| [0003](0003-core-v0.md) | Core v0: interpreter, checker, run/check/test/build | done |
| [0004](0004-snake.md) | Test project 1: Snake | done |
| [0005](0005-hello-web.md) | Test project 2a: Hello web | done |
| [0006](0006-blind-test.md) | Blind usability test: todo-cli from LANGUAGE.md only | done (merged in 0018) |
| [0007](0007-self-hosting-plan.md) | Plan: self-hosted native GPLM, Go only for bootstrap | done |
| [0008](0008-front-end.md) | Compiler front end in GPLM | done |
| [0009](0009-native-back-end.md) | Native back end in GPLM; self-hosting fixpoint | done |
| [0010](0010-remove-go.md) | Go removed; both test projects pass on the native core | done |
| [0011](0011-cross-platform-plan.md) | Windows x64, macOS x86-64/arm64 targets + CI | implemented, awaiting CI |
| [0012](0012-hex-literals.md) | Hexadecimal integer literals; compiler constants in hex | done |
| [0013](0013-reference-counting.md) | Compiler-inferred reference counting | done |
| [0014](0014-snake-gui.md) | Snake with a GUI (X11 protocol in GPLM) | done |
| [0015](0015-demo3d.md) | 3D demo scene: software renderer in GPLM | done |
