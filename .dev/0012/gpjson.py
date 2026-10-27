#!/usr/bin/env python3
"""JSON program tree (ast-json.md) -> GPLM text, for arm (b) of step 0012.

  gpjson.py convert prog.json out.gp     # writes out.gp; schema errors name JSON paths
  gpjson.py check   prog.json out.gp     # convert, then `kaizo check --json`, diagnostics as JSON paths
  gpjson.py map     out.gp LINE:COL      # JSON path of the node at a generated position

Pure tooling: it neither fixes nor completes the agent's program. The source map is written to
out.gp.map (one JSON object: "line:col" -> path).
"""
import json, os, re, subprocess, sys

KAIZO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "build", "kaizo")


class SchemaError(Exception):
    pass


class Out:
    def __init__(self):
        self.lines = [""]
        self.map = {}

    def mark(self, path):
        key = "%d:%d" % (len(self.lines), len(self.lines[-1]) + 1)
        self.map[key] = path  # innermost node starting here wins

    def w(self, s):
        self.lines[-1] += s

    def nl(self, ind):
        self.lines.append("  " * ind)


def need(node, path, *fields):
    if not isinstance(node, dict):
        raise SchemaError("%s: expected an object, found %s" % (path, json.dumps(node)[:40]))
    for f in fields:
        if f not in node:
            raise SchemaError("%s: missing field %r" % (path, f))


def lst(v, path):
    if not isinstance(v, list):
        raise SchemaError("%s: expected a list" % path)
    return v


def name(v, path):
    if not isinstance(v, str) or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", v):
        raise SchemaError("%s: expected a name, found %s" % (path, json.dumps(v)))
    return v


def lit_str(s, path):
    if not isinstance(s, str):
        raise SchemaError("%s: expected a string" % path)
    esc = {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\t": "\\t", "\r": "\\r", "\0": "\\0", "\x1b": "\\e"}
    out = []
    for ch in s:
        if ch in esc:
            out.append(esc[ch])
        elif ord(ch) < 32 or ord(ch) == 127:
            raise SchemaError("%s: control byte %d cannot be written in a string literal" % (path, ord(ch)))
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def typex(t, path):
    need(t, path, "name", "args")
    n = name(t["name"], path + ".name")
    args = [typex(a, "%s.args[%d]" % (path, i)) for i, a in enumerate(lst(t["args"], path + ".args"))]
    if n == "Fn":
        if not args:
            raise SchemaError("%s: Fn type needs at least the return type" % path)
        return "Fn(%s) -> %s" % (", ".join(args[:-1]), args[-1])
    return n + ("[%s]" % ", ".join(args) if args else "")


def block(o, stmts, path, ind):
    stmts = lst(stmts, path)
    if not stmts:
        raise SchemaError("%s: a block needs at least one statement" % path)
    for i, s in enumerate(stmts):
        p = "%s[%d]" % (path, i)
        need(s, p, "let_name", "x")
        o.nl(ind)
        o.mark(p)
        if s["let_name"] != "":
            o.w("let %s = " % name(s["let_name"], p + ".let_name"))
        expr(o, s["x"], p + ".x", ind)


def fields(o, fs, path, ind):
    for i, f in enumerate(lst(fs, path)):
        p = "%s[%d]" % (path, i)
        need(f, p, "name", "x")
        if i:
            o.w(", ")
        o.mark(p)
        o.w(name(f["name"], p + ".name") + ": ")
        expr(o, f["x"], p + ".x", ind)


def expr(o, e, path, ind):
    need(e, path, "k")
    k = e["k"]
    o.mark(path)
    if k == "EInt":
        need(e, path, "v")
        if not isinstance(e["v"], int) or isinstance(e["v"], bool):
            raise SchemaError("%s.v: expected an integer" % path)
        o.w(str(e["v"]))
    elif k == "EStr":
        need(e, path, "v")
        o.w(lit_str(e["v"], path + ".v"))
    elif k == "EBool":
        need(e, path, "v")
        if not isinstance(e["v"], bool):
            raise SchemaError("%s.v: expected true or false" % path)
        o.w("true" if e["v"] else "false")
    elif k in ("EVar", "ECtor"):
        need(e, path, "name")
        o.w(name(e["name"], path + ".name"))
    elif k == "ECall":
        need(e, path, "f", "args")
        expr(o, e["f"], path + ".f", ind)
        o.w("(")
        for i, a in enumerate(lst(e["args"], path + ".args")):
            if i:
                o.w(", ")
            expr(o, a, "%s.args[%d]" % (path, i), ind)
        o.w(")")
    elif k == "EField":
        need(e, path, "x", "name")
        expr(o, e["x"], path + ".x", ind)
        o.w("." + name(e["name"], path + ".name"))
    elif k == "EList":
        need(e, path, "items")
        o.w("[")
        for i, a in enumerate(lst(e["items"], path + ".items")):
            if i:
                o.w(", ")
            expr(o, a, "%s.items[%d]" % (path, i), ind)
        o.w("]")
    elif k == "ERec":
        need(e, path, "type", "fields")
        o.w(name(e["type"], path + ".type") + " { ")
        fields(o, e["fields"], path + ".fields", ind)
        o.w(" }")
    elif k == "EUpd":
        need(e, path, "x", "fields")
        o.w("{ ")
        expr(o, e["x"], path + ".x", ind)
        o.w(" with ")
        fields(o, e["fields"], path + ".fields", ind)
        o.w(" }")
    elif k == "EIf":
        need(e, path, "conds", "thens", "else")
        conds, thens = lst(e["conds"], path + ".conds"), lst(e["thens"], path + ".thens")
        if not conds or len(conds) != len(thens):
            raise SchemaError("%s: conds and thens must be non-empty and of equal length" % path)
        for i, c in enumerate(conds):
            o.w("if " if i == 0 else "elif ")
            expr(o, c, "%s.conds[%d]" % (path, i), ind + 1)
            o.w(" then")
            block(o, thens[i], "%s.thens[%d]" % (path, i), ind + 1)
            o.nl(ind)
        o.w("else")
        block(o, e["else"], path + ".else", ind + 1)
        o.nl(ind)
        o.w("end")
    elif k == "EMatch":
        need(e, path, "x", "arms")
        o.w("match ")
        expr(o, e["x"], path + ".x", ind + 1)
        arms = lst(e["arms"], path + ".arms")
        if not arms:
            raise SchemaError("%s.arms: a match needs at least one arm" % path)
        for i, a in enumerate(arms):
            p = "%s.arms[%d]" % (path, i)
            need(a, p, "pat", "body")
            o.nl(ind + 1)
            o.w("case ")
            pat(o, a["pat"], p + ".pat")
            o.w(" ->")
            block(o, a["body"], p + ".body", ind + 2)
        o.nl(ind)
        o.w("end")
    elif k == "ELam":
        need(e, path, "params", "body")
        ps = [name(p, "%s.params[%d]" % (path, i)) for i, p in enumerate(lst(e["params"], path + ".params"))]
        o.w("fn(%s)" % ", ".join(ps))
        block(o, e["body"], path + ".body", ind + 1)
        o.nl(ind)
        o.w("end")
    else:
        raise SchemaError("%s: unknown expression kind %r" % (path, k))


def pat(o, p, path):
    need(p, path, "k")
    k = p["k"]
    o.mark(path)
    if k == "PWild":
        o.w("_")
    elif k == "PVar":
        need(p, path, "name")
        o.w(name(p["name"], path + ".name"))
    elif k == "PInt":
        need(p, path, "v")
        if not isinstance(p["v"], int) or isinstance(p["v"], bool):
            raise SchemaError("%s.v: expected an integer" % path)
        o.w(str(p["v"]))
    elif k == "PStr":
        need(p, path, "v")
        o.w(lit_str(p["v"], path + ".v"))
    elif k == "PBool":
        need(p, path, "v")
        o.w("true" if p["v"] is True else "false")
    elif k == "PCtor":
        need(p, path, "name", "args")
        o.w(name(p["name"], path + ".name"))
        args = lst(p["args"], path + ".args")
        if args:
            o.w("(")
            for i, a in enumerate(args):
                if i:
                    o.w(", ")
                pat(o, a, "%s.args[%d]" % (path, i))
            o.w(")")
    elif k == "PList":
        need(p, path, "items", "rest")
        o.w("[")
        items = lst(p["items"], path + ".items")
        for i, a in enumerate(items):
            if i:
                o.w(", ")
            pat(o, a, "%s.items[%d]" % (path, i))
        if p["rest"] is not None:
            o.w(", .." if items else "..")
            pat(o, p["rest"], path + ".rest")
        o.w("]")
    else:
        raise SchemaError("%s: unknown pattern kind %r" % (path, k))


def program(prog):
    o = Out()
    need(prog, "$", "imports", "types", "lets", "fns", "tests")
    for i, m in enumerate(lst(prog["imports"], "imports")):
        o.mark("imports[%d]" % i)
        o.w("import " + name(m, "imports[%d]" % i))
        o.nl(0)
    for i, t in enumerate(lst(prog["types"], "types")):
        p = "types[%d]" % i
        need(t, p, "name", "tparams", "is_record", "ctors", "fields")
        o.nl(0)
        o.mark(p)
        tps = [name(x, p + ".tparams") for x in lst(t["tparams"], p + ".tparams")]
        o.w("type %s%s = " % (name(t["name"], p + ".name"), "[%s]" % ", ".join(tps) if tps else ""))
        if t["is_record"] is True:
            fs = []
            for j, f in enumerate(lst(t["fields"], p + ".fields")):
                need(f, "%s.fields[%d]" % (p, j), "name", "ty")
                fs.append("%s: %s" % (name(f["name"], p + ".fields"), typex(f["ty"], "%s.fields[%d].ty" % (p, j))))
            o.w("{ %s } end" % ", ".join(fs))
        else:
            cs = []
            for j, c in enumerate(lst(t["ctors"], p + ".ctors")):
                cp = "%s.ctors[%d]" % (p, j)
                need(c, cp, "name", "args")
                args = [typex(a, "%s.args[%d]" % (cp, m)) for m, a in enumerate(lst(c["args"], cp + ".args"))]
                cs.append(name(c["name"], cp + ".name") + ("(%s)" % ", ".join(args) if args else ""))
            if not cs:
                raise SchemaError("%s.ctors: a sum type needs at least one constructor" % p)
            o.w(" | ".join(cs) + " end")
        o.nl(0)
    for i, l in enumerate(lst(prog["lets"], "lets")):
        p = "lets[%d]" % i
        need(l, p, "name", "x")
        o.nl(0)
        o.mark(p)
        o.w("let %s = " % name(l["name"], p + ".name"))
        expr(o, l["x"], p + ".x", 0)
        o.nl(0)
    for i, f in enumerate(lst(prog["fns"], "fns")):
        p = "fns[%d]" % i
        need(f, p, "name", "params", "ret", "effects", "body")
        o.nl(0)
        o.mark(p)
        ps = []
        for j, a in enumerate(lst(f["params"], p + ".params")):
            ap = "%s.params[%d]" % (p, j)
            need(a, ap, "name", "ty")
            if a["ty"] is None:
                raise SchemaError("%s.ty: parameters of a top-level fn need a type" % ap)
            ps.append("%s: %s" % (name(a["name"], ap + ".name"), typex(a["ty"], ap + ".ty")))
        effs = [name(x, p + ".effects") for x in lst(f["effects"], p + ".effects")]
        o.w("fn %s(%s) -> %s%s" % (name(f["name"], p + ".name"), ", ".join(ps), typex(f["ret"], p + ".ret"),
                                    " ! [%s]" % ", ".join(effs) if effs else ""))
        block(o, f["body"], p + ".body", 1)
        o.nl(0)
        o.w("end")
        o.nl(0)
    for i, t in enumerate(lst(prog["tests"], "tests")):
        p = "tests[%d]" % i
        need(t, p, "name", "body")
        o.nl(0)
        o.mark(p)
        o.w("test " + lit_str(t["name"], p + ".name"))
        block(o, t["body"], p + ".body", 1)
        o.nl(0)
        o.w("end")
        o.nl(0)
    return "\n".join(l.rstrip() for l in o.lines) + "\n", o.map


def convert(src, dst):
    try:
        prog = json.load(open(src))
    except json.JSONDecodeError as e:
        print("json: %s" % e)
        return False
    try:
        text, m = program(prog)
    except SchemaError as e:
        print("schema: %s" % e)
        return False
    open(dst, "w").write(text)
    json.dump(m, open(dst + ".map", "w"))
    return True


def lookup(gp, line, col):
    m = json.load(open(gp + ".map"))
    best = None
    for key, path in m.items():
        l, c = map(int, key.split(":"))
        if (l, c) <= (line, col) and (best is None or (l, c) > best[0]):
            best = ((l, c), path)
    return best[1] if best else "?"


def main(argv):
    if len(argv) == 4 and argv[1] == "convert":
        return 0 if convert(argv[2], argv[3]) else 1
    if len(argv) == 4 and argv[1] == "check":
        if not convert(argv[2], argv[3]):
            return 1
        r = subprocess.run([KAIZO, "check", "--json", argv[3]], capture_output=True, text=True)
        if r.returncode == 0:
            print("ok")
            return 0
        for d in json.loads(r.stdout):
            print("%s: error: %s%s" % (lookup(argv[3], d["line"], d["col"]), d["message"],
                                       "\n  hint: " + d["hint"] if d.get("hint") else ""))
        return 1
    if len(argv) == 4 and argv[1] == "map":
        l, c = map(int, argv[3].split(":"))
        print(lookup(argv[2], l, c))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
