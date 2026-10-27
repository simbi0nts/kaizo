# Step 0018 — Phase 0: consolidation
Date: 2026-10-27
Status: done, except CI (no git remote yet)

## Goal
Phase 0 of ROADMAP.md: one linear history, no orphan branches, a rule so parallel agents stop
colliding on step numbers, CI ready to run.

## What was done
| Branch | Content | Result on main |
|---|---|---|
| claude/nifty-edison-01274c | blind test v1 (todo-cli) | merged as **0006**; the app, written for the Go v0 interpreter, passes unchanged on the native RC core |
| claude/modest-borg-dac383 | blind test v2: text vs JSON AST vs raw x86 | merged as **0016** (was 0012); acceptance 7/7 re-run on the current core |
| claude/quizzical-panini-cb943e | `list_sort_by` | merged as **0017** (was 0013); seed rebuilt on top of reference counting |

- Step-number rule added to `.dev/README.md` (claim a number in STATUS.md "Reserved steps" first).
- Test suites now 13 (todo-cli and wordfreq added to `make test` and the CI platform script).
- Verified after the merges: `make all` (13 suites), `make selfhost` (fixpoint), `make e2e` (13), `make gui` (8).

## Blocked
CI (`.github/workflows/ci.yml`) cannot run without a remote. Human: create a GitHub repository,
`git remote add origin …`, `git push -u origin main`. Until then Windows/macOS stay verified only
structurally (objdump, tests/macho_check.py).

## Next
0019 — static type checker (Phase 1).
