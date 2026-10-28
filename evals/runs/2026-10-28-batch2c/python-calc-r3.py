import sys
import threading


class CalcSyntaxError(Exception):
    def __init__(self, col):
        super().__init__(col)
        self.col = col


class CalcDivZero(Exception):
    pass


def tokenize(line):
    """Return list of (kind, value, col). kind in 'num', 'op', 'bad', 'end'."""
    toks = []
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if c in ' \t\r\n\f\v':
            i += 1
            continue
        if '0' <= c <= '9':
            j = i
            while j < n and '0' <= line[j] <= '9':
                j += 1
            toks.append(('num', int(line[i:j]), i + 1))
            i = j
            continue
        if c in '+-*/%()':
            toks.append(('op', c, i + 1))
        else:
            toks.append(('bad', c, i + 1))
        i += 1
    toks.append(('end', None, n + 1))
    return toks


class Parser:
    def __init__(self, line):
        self.toks = tokenize(line)
        self.pos = 0

    def peek(self):
        return self.toks[self.pos]

    def is_op(self, chars):
        t = self.toks[self.pos]
        return t[0] == 'op' and t[1] in chars

    def fail(self):
        raise CalcSyntaxError(self.toks[self.pos][2])

    def parse(self):
        node = self.expr()
        if self.peek()[0] != 'end':
            self.fail()
        return node

    def expr(self):
        node = self.term()
        while self.is_op('+-'):
            op = self.peek()[1]
            self.pos += 1
            node = (op, node, self.term())
        return node

    def term(self):
        node = self.unary()
        while self.is_op('*/%'):
            op = self.peek()[1]
            self.pos += 1
            node = (op, node, self.unary())
        return node

    def unary(self):
        count = 0
        while self.is_op('-'):
            count += 1
            self.pos += 1
        node = self.primary()
        for _ in range(count):
            node = ('neg', node)
        return node

    def primary(self):
        t = self.peek()
        if t[0] == 'num':
            self.pos += 1
            return ('num', t[1])
        if t[0] == 'op' and t[1] == '(':
            self.pos += 1
            node = self.expr()
            if not self.is_op(')'):
                self.fail()
            self.pos += 1
            return node
        self.fail()


def cdiv(a, b):
    if b == 0:
        raise CalcDivZero()
    q = abs(a) // abs(b)
    if (a < 0) != (b < 0):
        q = -q
    return q


def cmod(a, b):
    if b == 0:
        raise CalcDivZero()
    return a - b * cdiv(a, b)


def evaluate(node):
    kind = node[0]
    if kind == 'num':
        return node[1]
    if kind == 'neg':
        return -evaluate(node[1])
    a = evaluate(node[1])
    b = evaluate(node[2])
    if kind == '+':
        return a + b
    if kind == '-':
        return a - b
    if kind == '*':
        return a * b
    if kind == '/':
        return cdiv(a, b)
    return cmod(a, b)


def calc_line(line):
    """Return (output_string or None, ok)."""
    line = line.rstrip('\n').rstrip('\r')
    if line.strip() == '':
        return None, True
    try:
        ast = Parser(line).parse()
    except CalcSyntaxError as e:
        return 'error: syntax at %d' % e.col, False
    try:
        return str(evaluate(ast)), True
    except CalcDivZero:
        return 'error: division by zero', False


def main():
    data = sys.stdin.read()
    lines = data.split('\n')
    if lines and lines[-1] == '':
        lines.pop()
    out = []
    all_ok = True
    for line in lines:
        res, ok = calc_line(line)
        if not ok:
            all_ok = False
        if res is not None:
            out.append(res)
    if out:
        sys.stdout.write('\n'.join(out) + '\n')
    sys.stdout.flush()
    return 0 if all_ok else 1


def test_precedence_and_assoc():
    assert calc_line('1 + 2 * 3')[0] == '7'
    assert calc_line('(1+2)*3')[0] == '9'
    assert calc_line('8-3-2')[0] == '3'
    assert calc_line('2*3%4')[0] == '2'
    assert calc_line('-(4 - 10) % 4')[0] == '2'
    assert calc_line('--3')[0] == '3'


def test_c_division():
    assert calc_line('-7/2')[0] == '-3'
    assert calc_line('-7%2')[0] == '-1'
    assert calc_line('7%-2')[0] == '1'
    assert calc_line('7 / (3 - 3)') == ('error: division by zero', False)
    assert calc_line('1 % 0')[0] == 'error: division by zero'


def test_syntax_errors():
    assert calc_line('2 *') == ('error: syntax at 4', False)
    assert calc_line('1 2')[0] == 'error: syntax at 3'
    assert calc_line('(1')[0] == 'error: syntax at 3'
    assert calc_line('1/0 )')[0] == 'error: syntax at 5'
    assert calc_line('a')[0] == 'error: syntax at 1'
    assert calc_line(')')[0] == 'error: syntax at 1'


def test_empty_line():
    assert calc_line('   ') == (None, True)
    assert calc_line('') == (None, True)


if __name__ == '__main__':
    sys.setrecursionlimit(1000000)
    threading.stack_size(512 * 1024 * 1024)
    result = [1]

    def runner():
        result[0] = main()

    t = threading.Thread(target=runner)
    t.start()
    t.join()
    sys.exit(result[0])
