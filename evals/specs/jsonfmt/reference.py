import sys
class Bad(Exception):
    def __init__(s, i): s.i = i
def parse(t):
    i = [0]; n = len(t)
    def ws():
        while i[0] < n and t[i[0]] in b" \t\n\r": i[0] += 1
    def lit(w, v):
        for k, ch in enumerate(w):
            if i[0] + k >= n or t[i[0] + k] != ch: raise Bad(i[0] + k)
        i[0] += len(w); return v
    def num():
        s = i[0]
        if t[i[0]:i[0]+1] == b"-": i[0] += 1
        if i[0] >= n: raise Bad(i[0])
        if t[i[0]] == ord("0"): i[0] += 1
        elif 49 <= t[i[0]] <= 57:
            while i[0] < n and 48 <= t[i[0]] <= 57: i[0] += 1
        else: raise Bad(i[0])
        return ("num", t[s:i[0]].decode())
    def string():
        i[0] += 1; out = bytearray()
        while True:
            if i[0] >= n: raise Bad(i[0])
            c = t[i[0]]
            if c == 34: i[0] += 1; return ("str", bytes(out))
            if c < 0x20: raise Bad(i[0])
            if c == 92:
                if i[0] + 1 >= n: raise Bad(i[0] + 1)
                e = t[i[0]+1]; m = {34: b'"', 92: b'\\', 47: b'/', 98: b'\b', 102: b'\f', 110: b'\n', 114: b'\r', 116: b'\t'}
                if e in m: out += m[e]; i[0] += 2; continue
                if e == ord("u"):
                    h = t[i[0]+2:i[0]+6]
                    for k in range(4):
                        if i[0]+2+k >= n or chr(t[i[0]+2+k]) not in "0123456789abcdefABCDEF": raise Bad(i[0]+2+k)
                    v = int(h, 16)
                    out += bytes([v]) if v < 0x80 else b"\x00U" + h.lower()
                    i[0] += 6; continue
                raise Bad(i[0] + 1)
            out.append(c); i[0] += 1
    def value():
        ws()
        if i[0] >= n: raise Bad(i[0])
        c = t[i[0]]
        if c == ord("{"):
            i[0] += 1; ws(); mem = []
            if t[i[0]:i[0]+1] == b"}": i[0] += 1; return ("obj", mem)
            while True:
                ws()
                if t[i[0]:i[0]+1] != b'"': raise Bad(i[0])
                k = string(); ws()
                if t[i[0]:i[0]+1] != b":": raise Bad(i[0])
                i[0] += 1; v = value(); mem.append((k, v)); ws()
                if t[i[0]:i[0]+1] == b",": i[0] += 1; continue
                if t[i[0]:i[0]+1] == b"}": i[0] += 1; return ("obj", mem)
                raise Bad(i[0])
        if c == ord("["):
            i[0] += 1; ws(); el = []
            if t[i[0]:i[0]+1] == b"]": i[0] += 1; return ("arr", el)
            while True:
                el.append(value()); ws()
                if t[i[0]:i[0]+1] == b",": i[0] += 1; continue
                if t[i[0]:i[0]+1] == b"]": i[0] += 1; return ("arr", el)
                raise Bad(i[0])
        if c == 34: return string()
        if c == ord("t"): return lit(b"true", ("lit", "true"))
        if c == ord("f"): return lit(b"false", ("lit", "false"))
        if c == ord("n"): return lit(b"null", ("lit", "null"))
        if c == ord("-") or 48 <= c <= 57: return num()
        raise Bad(i[0])
    v = value(); ws()
    if i[0] < n: raise Bad(i[0])
    return v
def esc(b):
    out = bytearray(b'"'); k = 0
    while k < len(b):
        c = b[k]
        if c == 0 and b[k+1:k+2] == b"U": out += b"\\u" + b[k+2:k+6]; k += 6; continue
        m = {34: b'\\"', 92: b'\\\\', 8: b'\\b', 12: b'\\f', 10: b'\\n', 13: b'\\r', 9: b'\\t'}
        if c in m: out += m[c]
        elif c < 0x20: out += b"\\u%04x" % c
        else: out.append(c)
        k += 1
    return bytes(out + b'"')
def fmt(v, ind):
    k = v[0]; p = b"  " * (ind + 1)
    if k == "str": return esc(v[1])
    if k in ("num", "lit"): return v[1].encode()
    if not v[1]: return b"[]" if k == "arr" else b"{}"
    if k == "arr": items = [p + fmt(x, ind + 1) for x in v[1]]; o, c = b"[", b"]"
    else: items = [p + esc(a[1]) + b": " + fmt(b, ind + 1) for a, b in v[1]]; o, c = b"{", b"}"
    return o + b"\n" + b",\n".join(items) + b"\n" + b"  " * ind + c
t = sys.stdin.buffer.read()
try: v = parse(t)
except Bad as e:
    pre = t[:e.i]; line = pre.count(b"\n") + 1; col = e.i - (pre.rfind(b"\n") + 1) + 1
    sys.stdout.write("error: line %d col %d\n" % (line, col)); sys.exit(1)
sys.stdout.buffer.write(fmt(v, 0) + b"\n")
