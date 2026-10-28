#!/usr/bin/env python3
"""Summarise evals/results.jsonl: per spec and arm, and totals per arm."""
import json, os, collections
path = os.path.join(os.path.dirname(__file__), "results.jsonl")
rows = [json.loads(l) for l in open(path)] if os.path.exists(path) else []
if not rows:
    print("no results yet"); raise SystemExit
na = lambda v: "n/a" if v is None else v
print("| batch | spec | arm | total tokens | time s | lines | chars | fix rounds | hidden | check errors | runtime errors |")
print("|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|")
for r in sorted(rows, key=lambda r: (r["batch"], r["spec"], r["arm"])):
    print(f'| {r["batch"]} | {r["spec"]} | {r["arm"]} | {na(r["total_tokens"])} | {na(r.get("wall_s"))} | {r.get("lines", "")} | {r.get("program_chars", "")} | {r["fix_rounds"]} | {r["hidden_passed"]}/{r["hidden_total"]} | {r["check_errors"]} | {r["runtime_errors"]} |')
tot = collections.defaultdict(lambda: collections.Counter())
for r in rows:
    t = tot[r["arm"]]; t["runs"] += 1
    if r["total_tokens"] is not None:
        t["tokens"] += r["total_tokens"]; t["measured"] += 1
    t["lines"] += r.get("lines", 0); t["fix"] += r["fix_rounds"]
    t["solved"] += r["hidden_passed"] == r["hidden_total"]
print()
for arm, t in sorted(tot.items()):
    print(f'{arm}: {t["runs"]} runs, solved {t["solved"]}, {t["tokens"]} total tokens over {t["measured"]} measured runs, {t["lines"]} lines, {t["fix"]} fix rounds')
