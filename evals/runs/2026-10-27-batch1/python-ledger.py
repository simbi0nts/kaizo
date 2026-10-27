#!/usr/bin/env python3
"""ledger: account balances from a list of transfers read on stdin."""
import re
import sys

NAME_RE = re.compile(r"[A-Za-z0-9_]+")
AMOUNT_RE = re.compile(r"[0-9]+")


class LedgerError(Exception):
    def __init__(self, line_no):
        super().__init__("error: line %d" % line_no)
        self.line_no = line_no


def parse_line(line):
    """Return (from, to, amount) or None if malformed."""
    parts = line.split(",")
    if len(parts) != 3:
        return None
    src, dst, amt = parts
    if not NAME_RE.fullmatch(src) or not NAME_RE.fullmatch(dst):
        return None
    if not AMOUNT_RE.fullmatch(amt):
        return None
    value = int(amt)
    if value <= 0:
        return None
    if src == dst:
        return None
    return src, dst, value


def compute_balances(lines):
    """lines: iterable of lines without newline. Returns dict name->balance.
    Raises LedgerError on the first malformed line."""
    balances = {}
    for i, raw in enumerate(lines, start=1):
        line = raw[:-1] if raw.endswith("\r") else raw
        if line == "":
            continue
        parsed = parse_line(line)
        if parsed is None:
            raise LedgerError(i)
        src, dst, value = parsed
        balances[src] = balances.get(src, 0) - value
        balances[dst] = balances.get(dst, 0) + value
    return balances


def format_balances(balances):
    names = sorted(balances, key=lambda n: n.encode("utf-8"))
    return "".join("%s %d\n" % (n, balances[n]) for n in names)


def split_input(text):
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return lines


def main():
    data = sys.stdin.buffer.read().decode("utf-8", errors="replace")
    try:
        balances = compute_balances(split_input(data))
    except LedgerError as e:
        sys.stdout.write("error: line %d\n" % e.line_no)
        sys.stdout.flush()
        return 1
    sys.stdout.write(format_balances(balances))
    sys.stdout.flush()
    return 0


# ---------------- unit tests ----------------

def test_example():
    text = "alice,bob,500\nbob,carol,200\n\ncarol,alice,50\n"
    b = compute_balances(split_input(text))
    assert format_balances(b) == "alice -450\nbob 300\ncarol 150\n"


def test_parse_line_rejects_malformed():
    assert parse_line("a,b,1") == ("a", "b", 1)
    assert parse_line("a,b") is None
    assert parse_line("a,b,1,2") is None
    assert parse_line("a,b,0") is None
    assert parse_line("a,b,000") is None
    assert parse_line("a,b,") is None
    assert parse_line("a,b,-5") is None
    assert parse_line("a,b,1.5") is None
    assert parse_line("a,a,5") is None
    assert parse_line(",b,5") is None
    assert parse_line("a-x,b,5") is None
    assert parse_line("a ,b,5") is None


def test_error_line_counts_empty_lines():
    text = "a,b,1\n\n\nx,x,3\nbad\n"
    try:
        compute_balances(split_input(text))
    except LedgerError as e:
        assert e.line_no == 4
    else:
        assert False, "expected error"


def test_sorted_byte_order_and_negative():
    b = compute_balances(["b,A,10", "a,_z,5"])
    assert format_balances(b) == "A 10\n_z 5\na -5\nb -10\n"


def test_large_input():
    lines = ["acc%d,acc%d,%d" % (i % 100, (i + 1) % 100, i + 1) for i in range(10000)]
    b = compute_balances(lines)
    assert sum(b.values()) == 0
    assert len(b) == 100


if __name__ == "__main__":
    sys.exit(main())
