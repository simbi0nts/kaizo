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

## Step numbers (rule since step 0018)

Several agents may work in parallel on branches, so numbers are **claimed before work starts**:
1. On `main`, add a line `NNNN — <title> — <branch or session>` under "Reserved steps" in
   `STATUS.md` and commit it. Take the next number after the highest one in the index *and* in the
   reserved list.
2. Do the work on the branch with that number. When it is merged, move the line to the index.
3. If a collision still happens, renumber the branch's step at merge time and write the original
   number in its Status line (as done for 0016 and 0017).

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
| [0016](0016-format-experiment.md) | Experiment: GPLM text vs JSON AST vs raw x86 as agent output | done |
| [0017](0017-list-sort-by.md) | list_sort_by: stable comparator sort | done |
| [0018](0018-phase0-consolidation.md) | Phase 0: branches merged, step-number rule, CI ready | done |
| [0019](0019-ci-real-hardware.md) | CI on real Windows/macOS: 2 bugs fixed, all 4 targets green | done |
| [0020](0020-type-checker.md) | Static type checker: inference, generics, records | done |
| [0021](0021-effect-types.md) | Function types carry effects | done |
| [0022](0022-phase1-exit.md) | Phase 1 exit: blind-test mistakes now all caught before run time | done |
| [0023](0023-eval-harness.md) | Eval harness + batch 1: GPLM vs Python, 8/8 solved, GPLM 2.2x slower | done |
| [0024](0024-eval-batch2.md) | Eval batch 2 (calc, csvsum, inventory, jsonfmt): 8/8 again, GPLM 2.3x slower | done |
| [0025](0025-shorter-gplm.md) | try statement, variadic builtins, read_all; re-measured on batch 2 | done |
| [0026](0026-eval-variance.md) | 3 runs per spec: noise 4–13%, GPLM 1.26x size / 1.97x time; 0025 effect within noise | done |
| [0027](0027-eval-weaker-model.md) | Haiku evals: Python 12/12 first try vs GPLM 9/12; missing-`end` diagnostic | done |
| [0028](0028-haiku-rerun.md) | Haiku GPLM re-run: 10/12 first try, fixed errors gone; operator and naming hints | done |
| [0029](0029-infix-operators.md) | T1a: infix operators + grouping, desugared to builtins | done |
| [0030](0030-benchmarks.md) | Benchmarks vs C/Rust: server 0.77x, render3d 17x, game 243x slower | done |
| [0031](0031-perf-quick-wins.md) | Sampling profiler; fast equality, bulk copy, slice views: game 243x→53x vs C | done |
