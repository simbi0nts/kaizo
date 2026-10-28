import re
import sys

NAME_RE = re.compile(r"[a-z0-9_]+")
QTY_RE = re.compile(r"[0-9]+")


def is_name(tok):
    return NAME_RE.fullmatch(tok) is not None


def parse_qty(tok):
    """Return a positive int for a valid quantity token, otherwise None."""
    if QTY_RE.fullmatch(tok) is None:
        return None
    value = int(tok)
    return value if value > 0 else None


class Inventory:
    def __init__(self):
        self.stock = {}   # (loc, item) -> qty, always > 0
        self.totals = {}  # item -> sum over all locations

    def get(self, loc, item):
        return self.stock.get((loc, item), 0)

    def add(self, loc, item, qty):
        key = (loc, item)
        self.stock[key] = self.stock.get(key, 0) + qty
        self.totals[item] = self.totals.get(item, 0) + qty

    def take(self, loc, item, qty):
        # caller guarantees the stock is at least qty
        key = (loc, item)
        left = self.stock[key] - qty
        if left:
            self.stock[key] = left
        else:
            del self.stock[key]
        self.totals[item] = self.totals.get(item, 0) - qty

    def report_lines(self):
        keys = sorted(k for k, v in self.stock.items() if v > 0)
        if not keys:
            return ["(empty)"]
        return [f"{loc} {item} {self.stock[(loc, item)]}" for loc, item in keys]


def apply_line(inv, n, line, out):
    """Process one input line, appending output to out. Returns True on error."""
    if line == "" or line.startswith("#"):
        return False
    words = line.split(" ")
    cmd = words[0]
    if cmd == "add" and len(words) == 4:
        _, loc, item, qs = words
        qty = parse_qty(qs)
        if is_name(loc) and is_name(item) and qty is not None:
            inv.add(loc, item, qty)
            return False
    elif cmd == "remove" and len(words) == 4:
        _, loc, item, qs = words
        qty = parse_qty(qs)
        if is_name(loc) and is_name(item) and qty is not None:
            if inv.get(loc, item) < qty:
                out.append(f"error: line {n}: not enough {item} at {loc}")
                return True
            inv.take(loc, item, qty)
            return False
    elif cmd == "move" and len(words) == 5:
        _, item, qs, src, dst = words
        qty = parse_qty(qs)
        if (is_name(item) and is_name(src) and is_name(dst)
                and qty is not None and src != dst):
            if inv.get(src, item) < qty:
                out.append(f"error: line {n}: not enough {item} at {src}")
                return True
            inv.take(src, item, qty)
            inv.add(dst, item, qty)
            return False
    elif cmd == "report" and len(words) == 1:
        out.extend(inv.report_lines())
        return False
    elif cmd == "total" and len(words) == 2:
        item = words[1]
        if is_name(item):
            out.append(f"{item} {inv.totals.get(item, 0)}")
            return False
    out.append(f"error: line {n}: bad command")
    return True


def run(lines):
    """Run all lines. Returns (output_lines, had_error)."""
    inv = Inventory()
    out = []
    failed = False
    for n, line in enumerate(lines, 1):
        if apply_line(inv, n, line, out):
            failed = True
    return out, failed


def main():
    data = sys.stdin.read()
    lines = [l[:-1] if l.endswith("\r") else l for l in data.split("\n")]
    out, failed = run(lines)
    if out:
        sys.stdout.write("\n".join(out) + "\n")
    return 1 if failed else 0


def test_parse_qty():
    assert parse_qty("5") == 5
    assert parse_qty("007") == 7
    assert parse_qty("0") is None
    assert parse_qty("-1") is None
    assert parse_qty("") is None
    assert parse_qty("1a") is None


def test_example_session():
    lines = [
        "add main apple 5",
        "add main pear 2",
        "move apple 3 main shop",
        "remove shop apple 4",
        "total apple",
        "report",
    ]
    out, failed = run(lines)
    assert out == [
        "error: line 4: not enough apple at shop",
        "apple 5",
        "main apple 2",
        "main pear 2",
        "shop apple 3",
    ]
    assert failed


def test_bad_commands_and_empty_report():
    out, failed = run(["", "# comment", "move a 1 x x", "report extra",
                       "frobnicate", "remove x y 1"])
    assert out == [
        "error: line 3: bad command",
        "error: line 4: bad command",
        "error: line 5: bad command",
        "error: line 6: not enough y at x",
    ]
    assert failed
    out, failed = run(["report"])
    assert out == ["(empty)"]
    assert not failed


if __name__ == "__main__":
    sys.exit(main())
