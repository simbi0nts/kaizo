#!/usr/bin/env python3
"""inventory: stock keeper driven by commands on standard input."""
import re
import sys

NAME_RE = re.compile(r'[a-z0-9_]+\Z')
QTY_RE = re.compile(r'[0-9]+\Z')


def is_name(s):
    return NAME_RE.match(s) is not None


def parse_qty(s):
    if QTY_RE.match(s) is None:
        return None
    v = int(s)
    if v == 0:
        return None
    return v


class Inventory:
    def __init__(self):
        self.stock = {}   # (loc, item) -> qty
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

    def report(self):
        if not self.stock:
            return ['(empty)']
        return ['%s %s %d' % (loc, item, q)
                for (loc, item), q in sorted(self.stock.items())]

    def total(self, item):
        return self.totals.get(item, 0)


def process(lines):
    """Run commands; return (output_lines, had_error)."""
    inv = Inventory()
    out = []
    err = False
    for idx, line in enumerate(lines):
        n = idx + 1
        if line == '' or line.startswith('#'):
            continue
        words = line.split(' ')
        bad = any(w == '' for w in words)
        cmd = words[0]
        ok = False
        if not bad:
            if cmd == 'add' and len(words) == 4:
                loc, item, q = words[1], words[2], parse_qty(words[3])
                if is_name(loc) and is_name(item) and q is not None:
                    inv.add(loc, item, q)
                    ok = True
            elif cmd == 'remove' and len(words) == 4:
                loc, item, q = words[1], words[2], parse_qty(words[3])
                if is_name(loc) and is_name(item) and q is not None:
                    ok = True
                    if not inv.remove(loc, item, q):
                        out.append('error: line %d: not enough %s at %s' % (n, item, loc))
                        err = True
            elif cmd == 'move' and len(words) == 5:
                item, q, src, dst = words[1], parse_qty(words[2]), words[3], words[4]
                if (is_name(item) and q is not None and is_name(src)
                        and is_name(dst) and src != dst):
                    ok = True
                    if not inv.move(item, q, src, dst):
                        out.append('error: line %d: not enough %s at %s' % (n, item, src))
                        err = True
            elif cmd == 'report' and len(words) == 1:
                out.extend(inv.report())
                ok = True
            elif cmd == 'total' and len(words) == 2:
                if is_name(words[1]):
                    out.append('%s %d' % (words[1], inv.total(words[1])))
                    ok = True
        if not ok:
            out.append('error: line %d: bad command' % n)
            err = True
    return out, err


def split_input(data):
    text = data.decode('utf-8', errors='replace')
    lines = text.split('\n')
    if lines and lines[-1] == '':
        lines.pop()
    return [l[:-1] if l.endswith('\r') else l for l in lines]


def main():
    data = sys.stdin.buffer.read()
    out, err = process(split_input(data))
    if out:
        sys.stdout.write('\n'.join(out) + '\n')
    sys.stdout.flush()
    return 1 if err else 0


# ---------------- unit tests ----------------

def test_example():
    lines = ['add main apple 5', 'add main pear 2', 'move apple 3 main shop',
             'remove shop apple 4', 'total apple', 'report']
    out, err = process(lines)
    assert out == ['error: line 4: not enough apple at shop', 'apple 5',
                   'main apple 2', 'main pear 2', 'shop apple 3']
    assert err is True


def test_bad_commands():
    lines = ['add a b 0', 'add a b -1', 'add A b 1', 'add a  b 1', ' report',
             'report ', 'move x 1 a a', 'total', 'frob', 'add a b 1 2', 'total B']
    out, err = process(lines)
    assert out == ['error: line %d: bad command' % i for i in range(1, 12)]
    assert err


def test_ignored_and_empty_report():
    out, err = process(['', '# comment', 'report', 'total x'])
    assert out == ['(empty)', 'x 0']
    assert err is False


def test_remove_to_zero_hides_from_report():
    out, err = process(['add a x 2', 'remove a x 2', 'report', 'move x 1 a b'])
    assert out == ['(empty)', 'error: line 4: not enough x at a']
    assert err


def test_sorting_and_split_input():
    lines = split_input(b'add b z 1\r\nadd a_1 y 2\nadd a x 3\nreport\n')
    out, err = process(lines)
    assert out == ['a x 3', 'a_1 y 2', 'b z 1']
    assert not err


if __name__ == '__main__':
    sys.exit(main())
