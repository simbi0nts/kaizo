#!/usr/bin/env python3
"""Summarise evals/results.jsonl: per spec and arm, and totals per arm."""
import json, os, collections
path = os.path.join(os.path.dirname(__file__), "results.jsonl")
rows = [json.loads(l) for l in open(path)] if os.path.exists(path) else []
if not rows:
    print("no results yet"); raise SystemExit
print("| spec | arm | total tokens | time s | lines | fix rounds | hidden | check errors | runtime errors |")
print("|---|---|---:|---:|---:|---:|---:|---:|---:|")
for r in sorted(rows, key=lambda r: (r["spec"], r["arm"])):
    print(f'| {r["spec"]} | {r["arm"]} | {r["total_tokens"]} | {r.get("wall_s", "")} | {r.get("lines", "")} | {r["fix_rounds"]} | {r["hidden_passed"]}/{r["hidden_total"]} | {r["check_errors"]} | {r["runtime_errors"]} |')
tot = collections.defaultdict(lambda: collections.Counter())
for r in rows:
    t = tot[r["arm"]]; t["runs"] += 1; t["tokens"] += r["total_tokens"]; t["fix"] += r["fix_rounds"]
    t["solved"] += r["hidden_passed"] == r["hidden_total"]
print()
for arm, t in sorted(tot.items()):
    print(f'{arm}: {t["runs"]} runs, solved {t["solved"]}, {t["tokens"]} total tokens, {t["fix"]} fix rounds')
