import re
import sys

NAME_RE = re.compile(r"[a-z0-9_]+")
QTY_RE = re.compile(r"[0-9]+")


def is_name(s):
    return NAME_RE.fullmatch(s) is not None


def parse_qty(s):
    if QTY_RE.fullmatch(s) is None:
        return None
    q = int(s)
    return q if q > 0 else None


class Inventory:
    def __init__(self):
        self.stock = {}   # (loc, item) -> qty, only non-zero entries
        self.totals = {}  # item -> qty summed over all locations

    def give(self, loc, item, qty):
        key = (loc, item)
        self.stock[key] = self.stock.get(key, 0) + qty
        self.totals[item] = self.totals.get(item, 0) + qty

    def take(self, loc, item, qty):
        key = (loc, item)
        have = self.stock.get(key, 0)
        if have < qty:
            return False
        if have == qty:
            del self.stock[key]
        else:
            self.stock[key] = have - qty
        left = self.totals[item] - qty
        if left:
            self.totals[item] = left
        else:
            del self.totals[item]
        return True

    def move(self, item, qty, frm, to):
        if self.stock.get((frm, item), 0) < qty:
            return False
        self.take(frm, item, qty)
        self.give(to, item, qty)
        return True

    def total(self, item):
        return self.totals.get(item, 0)

    def report_lines(self):
        return ["%s %s %d" % (loc, item, self.stock[(loc, item)])
                for loc, item in sorted(self.stock)]


def _bad(n, out):
    out.append("error: line %d: bad command" % n)
    return True


def execute(inv, words, n, out):
    """Run one command, append its output lines to out. Return True on error."""
    if not all(words):
        return _bad(n, out)
    cmd, args = words[0], words[1:]

    if cmd == "add" and len(args) == 3:
        loc, item, qty = args
        q = parse_qty(qty)
        if q is not None and is_name(loc) and is_name(item):
            inv.give(loc, item, q)
            return False

    elif cmd == "remove" and len(args) == 3:
        loc, item, qty = args
        q = parse_qty(qty)
        if q is not None and is_name(loc) and is_name(item):
            if inv.take(loc, item, q):
                return False
            out.append("error: line %d: not enough %s at %s" % (n, item, loc))
            return True

    elif cmd == "move" and len(args) == 4:
        item, qty, frm, to = args
        q = parse_qty(qty)
        if (q is not None and is_name(item) and is_name(frm)
                and is_name(to) and frm != to):
            if inv.move(item, q, frm, to):
                return False
            out.append("error: line %d: not enough %s at %s" % (n, item, frm))
            return True

    elif cmd == "report" and not args:
        out.extend(inv.report_lines() or ["(empty)"])
        return False

    elif cmd == "total" and len(args) == 1:
        item = args[0]
        if is_name(item):
            out.append("%s %d" % (item, inv.total(item)))
            return False

    return _bad(n, out)


def run(lines):
    """Process command lines. Returns (output_lines, exit_code)."""
    inv = Inventory()
    out = []
    failed = False
    for n, raw in enumerate(lines, 1):
        line = raw.rstrip("\r\n")
        if line == "" or line.startswith("#"):
            continue
        if execute(inv, line.split(" "), n, out):
            failed = True
    return out, (1 if failed else 0)


def main():
    text = sys.stdin.read()
    out, code = run(text.split("\n"))
    if out:
        sys.stdout.write("\n".join(out) + "\n")
    sys.exit(code)


def test_example():
    lines = ["add main apple 5", "add main pear 2", "move apple 3 main shop",
             "remove shop apple 4", "total apple", "report"]
    out, code = run(lines)
    assert out == ["error: line 4: not enough apple at shop", "apple 5",
                   "main apple 2", "main pear 2", "shop apple 3"]
    assert code == 1


def test_failed_move_changes_nothing():
    out, code = run(["add a x 1", "move x 2 a b", "report"])
    assert out == ["error: line 2: not enough x at a", "a x 1"]
    assert code == 1


def test_bad_commands_and_ignored_lines():
    lines = ["", "# comment", "add a x 0", "add a x -1",
             "add  a x 1", "move x 1 a a", "report"]
    out, code = run(lines)
    assert out == ["error: line 3: bad command", "error: line 4: bad command",
                   "error: line 5: bad command", "error: line 6: bad command",
                   "(empty)"]
    assert code == 1


def test_clean_run():
    out, code = run(["add a x 2", "report", "total x"])
    assert out == ["a x 2", "x 2"]
    assert code == 0


if __name__ == "__main__":
    main()
