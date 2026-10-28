import re
import sys

NAME_RE = re.compile(r'[a-z0-9_]+')
QTY_RE = re.compile(r'[0-9]+')


def is_name(s):
    return NAME_RE.fullmatch(s) is not None


def parse_qty(s):
    """Return a positive int for valid quantity text, otherwise None."""
    if QTY_RE.fullmatch(s) is None:
        return None
    value = int(s)
    return value if value > 0 else None


class Inventory:
    def __init__(self):
        self.stock = {}

    def get(self, loc, item):
        return self.stock.get((loc, item), 0)

    def add(self, loc, item, qty):
        self.stock[(loc, item)] = self.get(loc, item) + qty

    def take(self, loc, item, qty):
        """Remove qty; return False and change nothing if not enough."""
        have = self.get(loc, item)
        if have < qty:
            return False
        left = have - qty
        if left:
            self.stock[(loc, item)] = left
        else:
            self.stock.pop((loc, item), None)
        return True

    def report_lines(self):
        keys = sorted(k for k, v in self.stock.items() if v > 0)
        if not keys:
            return ['(empty)']
        return ['%s %s %d' % (loc, item, self.stock[(loc, item)]) for loc, item in keys]

    def total(self, item):
        return sum(v for (loc, it), v in self.stock.items() if it == item)


def run_line(inv, n, line):
    """Process one input line. Returns (output_lines, had_error)."""
    bad = ['error: line %d: bad command' % n]

    if line == '' or line.startswith('#'):
        return [], False

    words = line.split(' ')
    if any(w == '' for w in words):
        return bad, True

    cmd, args = words[0], words[1:]

    if cmd == 'add' and len(args) == 3:
        loc, item, qty_text = args
        qty = parse_qty(qty_text)
        if is_name(loc) and is_name(item) and qty is not None:
            inv.add(loc, item, qty)
            return [], False
        return bad, True

    if cmd == 'remove' and len(args) == 3:
        loc, item, qty_text = args
        qty = parse_qty(qty_text)
        if not (is_name(loc) and is_name(item) and qty is not None):
            return bad, True
        if not inv.take(loc, item, qty):
            return ['error: line %d: not enough %s at %s' % (n, item, loc)], True
        return [], False

    if cmd == 'move' and len(args) == 4:
        item, qty_text, src, dst = args
        qty = parse_qty(qty_text)
        if not (is_name(item) and is_name(src) and is_name(dst) and qty is not None):
            return bad, True
        if src == dst:
            return bad, True
        if not inv.take(src, item, qty):
            return ['error: line %d: not enough %s at %s' % (n, item, src)], True
        inv.add(dst, item, qty)
        return [], False

    if cmd == 'report' and len(args) == 0:
        return inv.report_lines(), False

    if cmd == 'total' and len(args) == 1:
        item = args[0]
        if not is_name(item):
            return bad, True
        return ['%s %d' % (item, inv.total(item))], False

    return bad, True


def main():
    inv = Inventory()
    had_error = False
    n = 0
    for raw in sys.stdin:
        n += 1
        line = raw.rstrip('\r\n')
        out_lines, err = run_line(inv, n, line)
        for out in out_lines:
            sys.stdout.write(out + '\n')
        if err:
            had_error = True
    sys.stdout.flush()
    return 1 if had_error else 0


def test_names_and_quantities():
    assert is_name('main_1') and is_name('a0')
    assert not is_name('') and not is_name('Main') and not is_name('a-b')
    assert parse_qty('5') == 5
    assert parse_qty('0') is None
    assert parse_qty('-1') is None and parse_qty('+1') is None and parse_qty('') is None


def test_add_remove_and_insufficient():
    inv = Inventory()
    assert run_line(inv, 1, 'add main apple 5') == ([], False)
    assert run_line(inv, 2, 'remove main apple 2') == ([], False)
    assert inv.get('main', 'apple') == 3
    out, err = run_line(inv, 3, 'remove main apple 9')
    assert out == ['error: line 3: not enough apple at main'] and err
    assert inv.get('main', 'apple') == 3


def test_move_and_same_location():
    inv = Inventory()
    run_line(inv, 1, 'add main apple 5')
    assert run_line(inv, 2, 'move apple 3 main shop') == ([], False)
    assert inv.get('main', 'apple') == 2 and inv.get('shop', 'apple') == 3
    out, err = run_line(inv, 3, 'move apple 1 main main')
    assert out == ['error: line 3: bad command'] and err
    out, err = run_line(inv, 4, 'move apple 9 shop main')
    assert out == ['error: line 4: not enough apple at shop'] and err


def test_report_total_and_ignored_lines():
    inv = Inventory()
    assert inv.report_lines() == ['(empty)']
    assert run_line(inv, 1, '') == ([], False)
    assert run_line(inv, 2, '# comment') == ([], False)
    run_line(inv, 3, 'add main pear 2')
    run_line(inv, 4, 'add main apple 5')
    run_line(inv, 5, 'add shop apple 3')
    assert inv.report_lines() == ['main apple 5', 'main pear 2', 'shop apple 3']
    assert run_line(inv, 6, 'total apple') == (['apple 8'], False)
    assert run_line(inv, 7, 'total kiwi') == (['kiwi 0'], False)
    out, err = run_line(inv, 8, 'frobnicate')
    assert out == ['error: line 8: bad command'] and err


if __name__ == '__main__':
    sys.exit(main())
