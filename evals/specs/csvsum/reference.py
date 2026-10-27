import sys, re
def parse(t):
    """records as lists of fields; raises (record_number) on bad quoting"""
    recs = []; i = 0; n = len(t); rec = []; field = ""; recno = 1
    if n == 0: return recs
    while True:
        if i < n and t[i] == '"':
            i += 1; field = ""
            while True:
                if i >= n: raise ValueError(recno)
                if t[i] == '"':
                    if i + 1 < n and t[i+1] == '"': field += '"'; i += 2; continue
                    i += 1; break
                field += t[i]; i += 1
            if i < n and t[i] not in ",\n": raise ValueError(recno)
        else:
            j = i
            while j < n and t[j] not in ",\n":
                if t[j] == '"': raise ValueError(recno)
                j += 1
            field = t[i:j]; i = j
        rec.append(field)
        if i < n and t[i] == ",": i += 1; continue
        recs.append(rec); rec = []; recno += 1
        if i < n and t[i] == "\n": i += 1
        if i >= n: return recs
def q(s): return '"' + s.replace('"', '""') + '"' if any(c in s for c in ',"\n') else s
def main(a):
    if len(a) != 2: print("usage: csvsum <group-column> <sum-column>"); return 2
    t = sys.stdin.read()
    if t == "": print("error: no header"); return 1
    try: recs = parse(t)
    except ValueError as e:
        if e.args[0] == 1: print("error: record 1"); return 1
        bad = e.args[0]; recs = None
    else: bad = None
    if recs is None:
        # still need the header to report missing columns first
        try: hdr = parse(t.split("\n")[0])[0]
        except ValueError: print("error: record 1"); return 1
    else: hdr = recs[0]
    for c in a:
        if c not in hdr: print("error: no column " + c); return 1
    gi, si = hdr.index(a[0]), hdr.index(a[1])
    sums = {}
    rows = recs[1:] if recs is not None else None
    if rows is None:
        good = parse_prefix(t, bad)
        rows = good[1:]
    for k, r in enumerate(rows, 2):
        if len(r) != len(hdr) or not re.fullmatch(r"-?[0-9]+", r[si]): print("error: record %d" % k); return 1
        sums[r[gi]] = sums.get(r[gi], 0) + int(r[si])
    if bad is not None: print("error: record %d" % bad); return 1
    for g in sorted(sums, key=lambda s: s.encode()): print("%s,%d" % (q(g), sums[g]))
    return 0
def parse_prefix(t, bad):
    """records before the bad one"""
    out = []
    for cut in range(len(t), -1, -1):
        try:
            r = parse(t[:cut])
            if len(r) == bad - 1 and (cut == 0 or t[cut-1] == "\n"): return r
        except ValueError: pass
    return out
sys.exit(main(sys.argv[1:]))
