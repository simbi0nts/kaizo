# evals — measuring GPLM against a baseline (Phase 2 of ROADMAP.md)

Each spec in `specs/<name>/` has `spec.md` (what the agent sees), `reference.py` and `cases/` (hidden
acceptance test). `score.sh <spec> <command...>` runs a candidate against the hidden cases.

## Protocol (one run = one spec × one arm)
1. A **fresh agent** (no memory of this repository) gets exactly the arm prompt `arms/<arm>.md` with
   `{spec.md}` and, for GPLM, `{LANGUAGE.md}` filled in. It has no tools: it only answers with a file.
2. The **orchestrator** saves the file and runs:
   - GPLM: `kaizo check` → diagnostics; `kaizo test` → own tests; then `kaizo build` + `score.sh`.
   - Python: `python3 -c "import ast; ast.parse(...)"` → syntax errors; run its `test_*` functions;
     then `score.sh <spec> python3 file.py`.
3. Any failure of step 2 is sent back verbatim (compiler diagnostics, failing own test, or — for the
   hidden test — only the *name* and diff of the first failing case). That is one **fix round**.
   At most 3 fix rounds.
4. Record one line in `results.jsonl`:
   `{"date", "batch", "spec", "arm", "model", "total_tokens", "wall_s", "lines", "fix_rounds", "hidden_passed",
     "hidden_total", "check_errors", "runtime_errors", "notes"}`; candidates go to `runs/<date>-<batch>/`.
5. `python3 evals/report.py` prints the comparison table.

The point is the comparison under identical conditions, so keep the prompts, the feedback and the
limits the same for every arm. Change the protocol only with a new .dev step.

## Tools
- `judge.sh <gplm|python> <spec> <file>` — step 2 for one candidate; prints the feedback for a fix round.
- `extract.py <transcript.jsonl> <out>` — takes the agent's code block out of its transcript.
- `run_py_tests.py <file>` — runs a Python candidate's `test_*` functions.
