#!/usr/bin/env python3
import re
import sys

NAME_RE = re.compile(r"[a-z0-9_]+")
QTY_RE = re.compile(r"[0-9]+")


def valid_name(s):
    return NAME_RE.fullmatch(s) is not None


def parse_qty(s):
    if QTY_RE.fullmatch(s) is None:
        return None
    v = int(s)
    if v == 0:
        return None
    return v


class Inventory:
    def __init__(self):
        self.stock = {}   # (loc, item) -> qty (only non-zero)
        self.totals = {}  # item -> qty

    def get(self, loc, item):
        return self.stock.get((loc, item), 0)

    def _change(self, loc, item, delta):
        key = (loc, item)
        v = self.stock.get(key, 0) + delta
        if v == 0:
            self.stock.pop(key, None)
        else:
            self.stock[key] = v
        t = self.totals.get(item, 0) + delta
        if t == 0:
            self.totals.pop(item, None)
        else:
            self.totals[item] = t

    def execute(self, line, n):
        """Run one line. Returns (output_lines, had_error)."""
        if line == "" or line.startswith("#"):
            return [], False
        bad = ["error: line %d: bad command" % n], True
        words = line.split(" ")
        cmd = words[0]
        if cmd in ("add", "remove"):
            if len(words) != 4:
                return bad
            loc, item, q = words[1], words[2], words[3]
            qty = parse_qty(q)
            if not valid_name(loc) or not valid_name(item) or qty is None:
                return bad
            if cmd == "add":
                self._change(loc, item, qty)
                return [], False
            if self.get(loc, item) < qty:
                return ["error: line %d: not enough %s at %s" % (n, item, loc)], True
            self._change(loc, item, -qty)
            return [], False
        if cmd == "move":
            if len(words) != 5:
                return bad
            item, q, src, dst = words[1], words[2], words[3], words[4]
            qty = parse_qty(q)
            if (not valid_name(item) or qty is None or not valid_name(src)
                    or not valid_name(dst) or src == dst):
                return bad
            if self.get(src, item) < qty:
                return ["error: line %d: not enough %s at %s" % (n, item, src)], True
            self._change(src, item, -qty)
            self._change(dst, item, qty)
            return [], False
        if cmd == "report":
            if len(words) != 1:
                return bad
            if not self.stock:
                return ["(empty)"], False
            out = []
            for (loc, item) in sorted(self.stock):
                out.append("%s %s %d" % (loc, item, self.stock[(loc, item)]))
            return out, False
        if cmd == "total":
            if len(words) != 2 or not valid_name(words[1]):
                return bad
            item = words[1]
            return ["%s %d" % (item, self.totals.get(item, 0))], False
        return bad


def run(text):
    """Pure: run a whole script. Returns (output_lines, exit_code)."""
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    inv = Inventory()
    out = []
    err = False
    for i, raw in enumerate(lines, 1):
        if raw.endswith("\r"):
            raw = raw[:-1]
        o, e = inv.execute(raw, i)
        out.extend(o)
        if e:
            err = True
    return out, (1 if err else 0)


def main():
    data = sys.stdin.buffer.read().decode("utf-8", errors="replace")
    out, code = run(data)
    if out:
        sys.stdout.write("\n".join(out) + "\n")
    sys.stdout.flush()
    sys.exit(code)


# ---------------- tests ----------------

def test_example():
    text = ("add main apple 5\nadd main pear 2\nmove apple 3 main shop\n"
            "remove shop apple 4\ntotal apple\nreport\n")
    out, code = run(text)
    assert out == [
        "error: line 4: not enough apple at shop",
        "apple 5",
        "main apple 2",
        "main pear 2",
        "shop apple 3",
    ]
    assert code == 1


def test_bad_commands():
    text = ("add main apple 0\nadd main Apple 1\nadd  main apple 1\nmove a 1 x x\n"
            "report x\nfoo\ntotal\nadd main apple -1\nadd main apple 1 \n")
    out, code = run(text)
    assert out == ["error: line %d: bad command" % i for i in range(1, 10)]
    assert code == 1


def test_empty_comments_and_ok_exit():
    text = "# comment\n\nreport\nadd a b 3\nremove a b 3\nreport\ntotal b\n"
    out, code = run(text)
    assert out == ["(empty)", "(empty)", "b 0"]
    assert code == 0


def test_move_failure_changes_nothing():
    inv = Inventory()
    inv.execute("add x i 2", 1)
    o, e = inv.execute("move i 3 x y", 2)
    assert e and o == ["error: line 2: not enough i at x"]
    assert inv.get("x", "i") == 2 and inv.get("y", "i") == 0


def test_report_sorted():
    out, _ = run("add b z 1\nadd a_ y 1\nadd a z 1\nadd a b 1\nreport\n")
    assert out == ["a b 1", "a z 1", "a_ y 1", "b z 1"]


if __name__ == "__main__":
    main()
