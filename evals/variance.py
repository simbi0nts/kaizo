#!/usr/bin/env python3
"""Pool repeated runs and print mean, spread and GPLM/Python ratios per spec.
usage: evals/variance.py gplm=batch2b,batch2c python=batch2,batch2c"""
import json, os, sys, statistics as st
path = os.path.join(os.path.dirname(__file__), "results.jsonl")
rows = [json.loads(l) for l in open(path)]
pick = dict(a.split("=", 1) for a in sys.argv[1:])
pick = {arm: b.split(",") for arm, b in pick.items()}
sel = [r for r in rows if r["arm"] in pick and r["batch"] in pick[r["arm"]] and r.get("total_tokens") is not None]
specs = sorted({r["spec"] for r in sel})
def s(xs):
    m = st.mean(xs)
    return m, (st.stdev(xs) / m * 100 if len(xs) > 1 else 0.0)
print("| spec | arm | runs | solved | chars mean (cv) | min-max | tokens mean (cv) | time s mean (cv) |")
print("|---|---|---:|---:|---:|---:|---:|---:|")
mean = {}
for sp in specs:
    for arm in sorted(pick):
        rs = [r for r in sel if r["spec"] == sp and r["arm"] == arm]
        if not rs: continue
        c, t, w = [r["program_chars"] for r in rs], [r["total_tokens"] for r in rs], [r["wall_s"] for r in rs]
        solved = sum(r["hidden_passed"] == r["hidden_total"] for r in rs)
        mean[(sp, arm)] = (s(c)[0], s(t)[0], s(w)[0])
        print(f"| {sp} | {arm} | {len(rs)} | {solved} | {s(c)[0]:.0f} ({s(c)[1]:.0f}%) | {min(c)}-{max(c)} | {s(t)[0]:.0f} ({s(t)[1]:.1f}%) | {s(w)[0]:.1f} ({s(w)[1]:.0f}%) |")
if "gplm" in pick and "python" in pick:
    print("\n| spec | chars | tokens | time |\n|---|---:|---:|---:|")
    tot = [[0, 0], [0, 0], [0, 0]]
    for sp in specs:
        g, p = mean.get((sp, "gplm")), mean.get((sp, "python"))
        if not (g and p): continue
        for i in range(3): tot[i][0] += g[i]; tot[i][1] += p[i]
        print(f"| {sp} | {g[0]/p[0]:.2f}x | {g[1]/p[1]:.2f}x | {g[2]/p[2]:.2f}x |")
    print(f"| all | {tot[0][0]/tot[0][1]:.2f}x | {tot[1][0]/tot[1][1]:.2f}x | {tot[2][0]/tot[2][1]:.2f}x |")
