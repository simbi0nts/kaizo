#!/usr/bin/env python3
"""Reference behaviour of the wordfreq spec (used only to produce expected outputs)."""
import re, sys
def main(argv):
    if len(argv) < 2:
        print("usage: wordfreq <file>"); return 2
    try:
        data = open(argv[1], "rb").read().decode("latin-1")
    except OSError:
        print("error: cannot read " + argv[1]); return 1
    counts = {}
    for w in re.findall(r"[A-Za-z]+", data):
        w = w.lower(); counts[w] = counts.get(w, 0) + 1
    for w, c in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[:10]:
        print(c, w)
    return 0
sys.exit(main(sys.argv))
