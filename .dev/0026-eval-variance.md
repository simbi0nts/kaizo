# Step 0026 — Repeated eval runs: how noisy are the numbers?
Date: 2026-10-28
Status: done

## Why
Steps 0023–0025 drew conclusions from one run per spec and arm. Step 0025's size effect (−7.6%)
was smaller than the run-to-run differences seen in jsonfmt (+15%), so the noise had to be measured
before any further language change is judged.

## What was done
- 16 more fresh agents (Claude Opus 5.5, same prompts and protocol, prompts pasted inline as before):
  runs 2 and 3 of each batch-2 spec (calc, csvsum, inventory, jsonfmt) for both arms, current GPLM
  (with try / variadic / read_all). Run 1 is batch2 (Python) and batch2b (GPLM).
- results.jsonl: batch `batch2c` with a new `run` field; candidates in `evals/runs/2026-10-28-batch2c/`.
- `evals/variance.py gplm=batch2b,batch2c python=batch2,batch2c` pools runs and prints mean,
  coefficient of variation, min–max and GPLM/Python ratios.

## Results (3 runs per spec and arm)
| spec | arm | chars mean (cv) | min–max | total tokens mean (cv) | time s mean (cv) |
|---|---|---:|---:|---:|---:|
| calc | GPLM | 5,606 (9%) | 5,176–6,158 | 54,038 (0.6%) | 48.9 (11%) |
| calc | Python | 5,053 (4%) | 4,857–5,220 | 47,954 (3.4%) | 27.5 (15%) |
| csvsum | GPLM | 6,777 (4%) | 6,553–7,062 | 57,390 (3.8%) | 75.7 (15%) |
| csvsum | Python | 4,934 (4%) | 4,725–5,081 | 48,838 (3.7%) | 37.8 (10%) |
| inventory | GPLM | 7,295 (13%) | 6,334–8,290 | 57,259 (0.6%) | 74.2 (7%) |
| inventory | Python | 5,216 (4%) | 4,988–5,364 | 48,163 (3.7%) | 29.4 (7%) |
| jsonfmt | GPLM | 9,054 (8%) | 8,608–9,933 | 62,858 (4.1%) | 117.1 (18%) |
| jsonfmt | Python | 7,660 (4%) | 7,378–7,992 | 52,715 (3.1%) | 65.8 (26%) |

GPLM/Python: chars 1.26x (calc 1.11, csvsum 1.37, inventory 1.40, jsonfmt 1.18), total tokens
1.17x, wall time 1.97x. **Correctness: 24/24 runs solved first try, 0 fix rounds** (all batches so
far: 44/44).

## Reading the result
- **Noise level**: program size varies 4% (cv) between Python runs and 4–13% between GPLM runs;
  GPLM varies more because agents pick different designs (e.g. inventory: a list of entries in one
  run, an AVL tree in another, +31% characters). Time varies 7–26%. Total tokens vary < 5% because
  the prompt dominates them.
- **With 3 runs per spec, a mean differs by ~5% from chance alone**; a size effect under ~10–15%
  per spec cannot be claimed. Step 0025's −7.6% is **not supported**: the single pre-0025 programs
  lie inside the post-0025 range for calc, inventory and jsonfmt; only csvsum (7,326) is above all
  three new runs (6,553–7,062), i.e. a real but local gain where `try` and `read_all` replaced the
  most boilerplate.
- **The gap to Python is robust**: in every spec every GPLM run is longer than the mean Python run
  except one calc run (0.99–1.27x). Time ~2x is consistent across all specs.
- **Correctness still saturates**: the specs separate the languages on cost, not on errors.

## Protocol change (evals/README.md)
Language changes are judged on ≥3 runs per spec and arm (pooled with `variance.py`), and an
effect is reported only when it exceeds the observed min–max range.

## Next
- Bigger levers for size and time (iteration form over ranges/strings, char literals), measured
  with ≥3 runs; or Phase 3 libraries; or harder correctness tests (larger programs, edits of an
  existing codebase) where the error rate is not zero.
