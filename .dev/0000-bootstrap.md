# Step 0000 — Repository bootstrap
Date: 2026-10-27
Status: done

## Goal
Make the project resumable from any machine: version control + step log.

## Decisions
- Git repo at the project root, branch `main`.
- Step log in `.dev/`, one file per step, index in `.dev/README.md`,
  live pointer in `.dev/STATUS.md`.
- Commit messages: `[step NNNN] <summary>`.
- Folder per part from specs "Theory 1": `core/`, `libs/`, `apps/<project>/`.
- `specs.md` stays human-only (its first line says so).

## What was done
- `git init`, folder skeleton, `.gitignore`, `.dev/` docs.
- Acceptance criteria for both test projects in `apps/*/ACCEPTANCE.md`.

## How to verify
`git log --oneline` shows a `[step 0000]` commit; `.dev/README.md` lists the step.

## Next step
0001 — concept proposal.
