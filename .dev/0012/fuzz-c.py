#!/usr/bin/env python3
"""Random differential test of a topword binary (arm c / control a2). Usage: fuzz-c.py <binary>"""
import random, subprocess, sys
r = random.Random(7); bad = 0; N = 500
def ref(s):
    ws = s.split()
    if not ws: return b""
    c, first = {}, {}
    for i, w in enumerate(ws): c[w] = c.get(w, 0) + 1; first.setdefault(w, i)
    return (max(c, key=lambda w: (c[w], -first[w])) + "\n").encode()
for t in range(N):
    nd = r.choice([1, 3, 10, 50, 200])
    vocab = list(dict.fromkeys("".join(r.choice("abcdefghij"[:r.randint(1, 10)]) for _ in range(r.randint(1, 32))) for _ in range(nd)))
    out, size, lim = [], 0, r.choice([20, 200, 4000])
    while True:
        w = r.choice(vocab); sep = r.choice([" ", "\n", "  "])
        if size + len(w) + len(sep) > lim: break
        out.append(w + sep); size += len(w) + len(sep)
    s = "".join(out)
    if r.random() < 0.3: s = s.rstrip()
    p = subprocess.run([sys.argv[1]], input=s.encode(), capture_output=True)
    if p.stdout != ref(s) or p.returncode != 0:
        bad += 1
        if bad < 4: print("MISMATCH len", len(s), "want", ref(s)[:40], "got", p.stdout[:40], "ec", p.returncode)
print("fuzz: %d / %d ok" % (N - bad, N))
