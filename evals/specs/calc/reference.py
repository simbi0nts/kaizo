import sys
class Syn(Exception):
    def __init__(s, col): s.col = col
class Div(Exception): pass
CHECK = [False]
def tdiv(a, b):
    if b == 0:
        if CHECK[0]: return 0
        raise Div()
    q = abs(a) // abs(b); return q if (a >= 0) == (b >= 0) else -q
def tmod(a, b):
    if b == 0:
        if CHECK[0]: return 0
        raise Div()
    return a - b * tdiv(a, b)
class P:
    def __init__(s, t): s.t = t; s.i = 0
    def ws(s):
        while s.i < len(s.t) and s.t[s.i] in " \t\r": s.i += 1
    def peek(s):
        s.ws(); return s.t[s.i] if s.i < len(s.t) else ""
    def expr(s):
        v = s.term()
        while s.peek() in ("+", "-") and s.peek():
            op = s.t[s.i]; s.i += 1; r = s.term(); v = v + r if op == "+" else v - r
        return v
    def term(s):
        v = s.unary()
        while s.peek() in ("*", "/", "%") and s.peek():
            op = s.t[s.i]; s.i += 1; r = s.unary()
            v = v * r if op == "*" else tdiv(v, r) if op == "/" else tmod(v, r)
        return v
    def unary(s):
        if s.peek() == "-": s.i += 1; return -s.unary()
        return s.primary()
    def primary(s):
        c = s.peek()
        if c == "(":
            s.i += 1; v = s.expr()
            if s.peek() != ")": raise Syn(s.i + 1)
            s.i += 1; return v
        if c.isdigit():
            j = s.i
            while j < len(s.t) and s.t[j].isdigit(): j += 1
            v = int(s.t[s.i:j]); s.i = j; return v
        raise Syn(s.i + 1)
CHECK = [False]
def ev(line):
    # pass 1: syntax only (division never fails), pass 2: evaluate
    for check in (True, False):
        CHECK[0] = check
        p = P(line); v = p.expr()
        if p.peek() != "": raise Syn(p.i + 1)
    return v
ok = True
for line in sys.stdin.read().split("\n"):
    if line.strip() == "": continue
    try: print(ev(line))
    except Syn as e: print("error: syntax at %d" % e.col); ok = False
    except Div: print("error: division by zero"); ok = False
sys.exit(0 if ok else 1)
