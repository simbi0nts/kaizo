import sys
import threading


class SyntaxErr(Exception):
    def __init__(self, col):
        super().__init__(col)
        self.col = col


def tokenize(line):
    toks = []
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if c in ' \t\f\v':
            i += 1
            continue
        if c.isdigit() and c in '0123456789':
            j = i
            while j < n and line[j] in '0123456789':
                j += 1
            toks.append(('num', int(line[i:j]), i + 1))
            i = j
            continue
        if c in '+-*/%()':
            toks.append((c, c, i + 1))
        else:
            toks.append(('bad', c, i + 1))
        i += 1
    toks.append(('end', None, n + 1))
    return toks


def tdiv(a, b):
    q = abs(a) // abs(b)
    if (a < 0) != (b < 0):
        q = -q
    return q


def tmod(a, b):
    return a - b * tdiv(a, b)


class Parser:
    def __init__(self, line):
        self.toks = tokenize(line)
        self.pos = 0
        self.divzero = False

    def peek(self):
        return self.toks[self.pos]

    def advance(self):
        t = self.toks[self.pos]
        self.pos += 1
        return t

    def parse(self):
        v = self.expr()
        t = self.peek()
        if t[0] != 'end':
            raise SyntaxErr(t[2])
        return v

    def expr(self):
        v = self.term()
        while self.peek()[0] in ('+', '-'):
            op = self.advance()[0]
            r = self.term()
            v = v + r if op == '+' else v - r
        return v

    def term(self):
        v = self.unary()
        while self.peek()[0] in ('*', '/', '%'):
            op = self.advance()[0]
            r = self.unary()
            if op == '*':
                v = v * r
            elif r == 0:
                self.divzero = True
                v = 0
            elif op == '/':
                v = tdiv(v, r)
            else:
                v = tmod(v, r)
        return v

    def unary(self):
        neg = 0
        while self.peek()[0] == '-':
            self.advance()
            neg += 1
        v = self.primary()
        return -v if neg % 2 else v

    def primary(self):
        t = self.peek()
        if t[0] == 'num':
            self.advance()
            return t[1]
        if t[0] == '(':
            self.advance()
            v = self.expr()
            t2 = self.peek()
            if t2[0] != ')':
                raise SyntaxErr(t2[2])
            self.advance()
            return v
        raise SyntaxErr(t[2])


def evaluate(line):
    """Return (ok, output_string) or None for blank lines."""
    if line.strip() == '':
        return None
    p = Parser(line)
    try:
        v = p.parse()
    except SyntaxErr as e:
        return (False, 'error: syntax at %d' % e.col)
    if p.divzero:
        return (False, 'error: division by zero')
    return (True, str(v))


def run():
    data = sys.stdin.read()
    lines = data.split('\n')
    out = []
    ok_all = True
    for line in lines:
        if line.endswith('\r'):
            line = line[:-1]
        res = evaluate(line)
        if res is None:
            continue
        ok, s = res
        if not ok:
            ok_all = False
        out.append(s)
    if out:
        sys.stdout.write('\n'.join(out) + '\n')
    sys.stdout.flush()
    return 0 if ok_all else 1


def main():
    sys.setrecursionlimit(1000000)
    result = [1]

    def target():
        result[0] = run()

    try:
        threading.stack_size(256 * 1024 * 1024)
    except (ValueError, RuntimeError):
        pass
    th = threading.Thread(target=target)
    th.start()
    th.join()
    sys.exit(result[0])


# ---------------- tests ----------------

def test_precedence_and_assoc():
    assert evaluate('1 + 2 * 3') == (True, '7')
    assert evaluate('(1+2)*3') == (True, '9')
    assert evaluate('8-3-2') == (True, '3')
    assert evaluate('2*3%4') == (True, '2')
    assert evaluate('-(4 - 10) % 4') == (True, '2')
    assert evaluate('--3') == (True, '3')


def test_truncating_division():
    assert evaluate('-7/2') == (True, '-3')
    assert evaluate('-7%2') == (True, '-1')
    assert evaluate('7%-2') == (True, '1')
    assert evaluate('7/-2') == (True, '-3')
    assert evaluate('7 / (3 - 3)') == (False, 'error: division by zero')
    assert evaluate('5 % 0') == (False, 'error: division by zero')


def test_syntax_errors():
    assert evaluate('2 *') == (False, 'error: syntax at 4')
    assert evaluate('1 2') == (False, 'error: syntax at 3')
    assert evaluate('(1') == (False, 'error: syntax at 3')
    assert evaluate('1/0 +') == (False, 'error: syntax at 6')
    assert evaluate('a') == (False, 'error: syntax at 1')
    assert evaluate(')') == (False, 'error: syntax at 1')


def test_blank():
    assert evaluate('') is None
    assert evaluate('   ') is None


if __name__ == '__main__':
    main()
