import re
import sys

NAME_RE = re.compile(r"[a-z0-9_]+")
QTY_RE = re.compile(r"[0-9]+")


def is_name(s):
    return NAME_RE.fullmatch(s) is not None


def parse_qty(s):
    if QTY_RE.fullmatch(s) is None:
        return None
    v = int(s)
    if v <= 0:
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
        if v:
            self.stock[key] = v
        else:
            self.stock.pop(key, None)
        t = self.totals.get(item, 0) + delta
        if t:
            self.totals[item] = t
        else:
            self.totals.pop(item, None)

    def add(self, loc, item, qty):
        self._change(loc, item, qty)

    def remove(self, loc, item, qty):
        if self.get(loc, item) < qty:
            return False
        self._change(loc, item, -qty)
        return True

    def move(self, item, qty, src, dst):
        if self.get(src, item) < qty:
            return False
        self._change(src, item, -qty)
        self._change(dst, item, qty)
        return True

    def report_lines(self):
        if not self.stock:
            return ["(empty)"]
        keys = sorted(self.stock, key=lambda k: (k[0].encode(), k[1].encode()))
        return ["%s %s %d" % (k[0], k[1], self.stock[k]) for k in keys]

    def total(self, item):
        return self.totals.get(item, 0)


def process_line(inv, line, n, out):
    """Process one line; append output lines to out. Return True if an error occurred."""
    if line == "" or line.startswith("#"):
        return False
    bad = "error: line %d: bad command" % n
    w = line.split(" ")
    cmd = w[0]
    if cmd == "add" or cmd == "remove":
        if len(w) != 4 or not is_name(w[1]) or not is_name(w[2]):
            out.append(bad)
            return True
        q = parse_qty(w[3])
        if q is None:
            out.append(bad)
            return True
        if cmd == "add":
            inv.add(w[1], w[2], q)
            return False
        if not inv.remove(w[1], w[2], q):
            out.append("error: line %d: not enough %s at %s" % (n, w[2], w[1]))
            return True
        return False
    if cmd == "move":
        if len(w) != 5 or not is_name(w[1]) or not is_name(w[3]) or not is_name(w[4]):
            out.append(bad)
            return True
        q = parse_qty(w[2])
        if q is None or w[3] == w[4]:
            out.append(bad)
            return True
        if not inv.move(w[1], q, w[3], w[4]):
            out.append("error: line %d: not enough %s at %s" % (n, w[1], w[3]))
            return True
        return False
    if cmd == "report":
        if len(w) != 1:
            out.append(bad)
            return True
        out.extend(inv.report_lines())
        return False
    if cmd == "total":
        if len(w) != 2 or not is_name(w[1]):
            out.append(bad)
            return True
        out.append("%s %d" % (w[1], inv.total(w[1])))
        return False
    out.append(bad)
    return True


def run(text):
    """Run a whole script. Returns (output_lines, exit_code)."""
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    inv = Inventory()
    out = []
    err = False
    for i, line in enumerate(lines, 1):
        if process_line(inv, line, i, out):
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
    text = ("add main apple 0\nadd Main apple 1\nadd main  apple 1\nmove a 1 x x\n"
            "foo\nreport x\ntotal\nadd main apple -1\nadd main apple 1 \n")
    out, code = run(text)
    assert out == ["error: line %d: bad command" % i for i in range(1, 10)]
    assert code == 1


def test_empty_and_comments():
    out, code = run("# hello\n\nreport\n")
    assert out == ["(empty)"]
    assert code == 0


def test_remove_to_zero_and_total():
    out, code = run("add a x 2\nremove a x 2\nreport\ntotal x\ntotal y\n")
    assert out == ["(empty)", "x 0", "y 0"]
    assert code == 0


def test_move_insufficient_changes_nothing():
    inv = Inventory()
    inv.add("a", "x", 1)
    assert not inv.move("x", 2, "a", "b")
    assert inv.get("a", "x") == 1 and inv.get("b", "x") == 0


def test_sort_byte_order():
    inv = Inventory()
    inv.add("b", "z", 1)
    inv.add("_a", "y", 1)
    inv.add("a", "b", 1)
    inv.add("a", "_", 1)
    assert inv.report_lines() == ["_a y 1", "a _ 1", "a b 1", "b z 1"]


if __name__ == "__main__":
    main()
