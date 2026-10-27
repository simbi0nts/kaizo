import sys, re
N = re.compile(r"[a-z0-9_]+"); Q = re.compile(r"[0-9]+")
def qty(s): return int(s) if Q.fullmatch(s) and int(s) > 0 else None
st = {}; ok = True
def put(k, v): st[k] = st.get(k, 0) + v
lines = sys.stdin.read().split("\n")
if lines and lines[-1] == "": lines.pop()
for n, l in enumerate(lines, 1):
    if l == "" or l.startswith("#"): continue
    w = l.split(" ")
    def bad():
        global ok; ok = False; print("error: line %d: bad command" % n)
    def short(item, loc):
        global ok; ok = False; print("error: line %d: not enough %s at %s" % (n, item, loc))
    c = w[0]
    if c in ("add", "remove") and len(w) == 4 and N.fullmatch(w[1]) and N.fullmatch(w[2]) and qty(w[3]):
        k = (w[1], w[2]); q = qty(w[3])
        if c == "add": put(k, q)
        elif st.get(k, 0) < q: short(w[2], w[1])
        else: put(k, -q)
    elif c == "move" and len(w) == 5 and N.fullmatch(w[1]) and qty(w[2]) and N.fullmatch(w[3]) and N.fullmatch(w[4]) and w[3] != w[4]:
        q = qty(w[2])
        if st.get((w[3], w[1]), 0) < q: short(w[1], w[3])
        else: put((w[3], w[1]), -q); put((w[4], w[1]), q)
    elif c == "report" and len(w) == 1:
        items = sorted((k for k in st if st[k] != 0), key=lambda k: (k[0].encode(), k[1].encode()))
        if not items: print("(empty)")
        for k in items: print("%s %s %d" % (k[0], k[1], st[k]))
    elif c == "total" and len(w) == 2 and N.fullmatch(w[1]):
        print("%s %d" % (w[1], sum(v for (loc, it), v in st.items() if it == w[1])))
    else: bad()
sys.exit(0 if ok else 1)
