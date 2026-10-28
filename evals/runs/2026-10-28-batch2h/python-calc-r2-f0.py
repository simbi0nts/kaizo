import sys


class _SyntaxErr(Exception):
    def __init__(self, col):
        super().__init__(col)
        self.col = col


class _DivZero(Exception):
    pass


class _Parser:
    """Recursive-descent parser. Builds a tuple AST; columns are 1-based indices into the original line."""

    def __init__(self, line):
        self.s = line
        self.n = len(line)
        self.i = 0

    def _skip(self):
        while self.i < self.n and self.s[self.i].isspace():
            self.i += 1

    def _peek(self):
        self._skip()
        return self.s[self.i] if self.i < self.n else None

    def _fail(self):
        self._skip()
        raise _SyntaxErr(self.i + 1)

    def parse_top(self):
        node = self.parse_expr()
        if self._peek() is not None:
            self._fail()
        return node

    def parse_expr(self):
        node = self.parse_term()
        while self._peek() in ('+', '-'):
            op = self.s[self.i]
            self.i += 1
            rhs = self.parse_term()
            node = (op, node, rhs)
        return node

    def parse_term(self):
        node = self.parse_unary()
        while self._peek() in ('*', '/', '%'):
            op = self.s[self.i]
            self.i += 1
            rhs = self.parse_unary()
            node = (op, node, rhs)
        return node

    def parse_unary(self):
        if self._peek() == '-':
            self.i += 1
            return ('neg', self.parse_unary())
        return self.parse_primary()

    def parse_primary(self):
        c = self._peek()
        if c is None:
            self._fail()
        if '0' <= c <= '9':
            start = self.i
            while self.i < self.n and '0' <= self.s[self.i] <= '9':
                self.i += 1
            return int(self.s[start:self.i])
        if c == '(':
            self.i += 1
            node = self.parse_expr()
            if self._peek() != ')':
                self._fail()
            self.i += 1
            return node
        self._fail()


def _eval(node):
    if isinstance(node, int):
        return node
    tag = node[0]
    if tag == 'neg':
        return -_eval(node[1])
    op, a, b = node
    x = _eval(a)
    y = _eval(b)
    if op == '+':
        return x + y
    if op == '-':
        return x - y
    if op == '*':
        return x * y
    # '/' or '%': truncate toward zero, remainder takes the sign of the dividend
    if y == 0:
        raise _DivZero()
    q = abs(x) // abs(y)
    if (x < 0) != (y < 0):
        q = -q
    if op == '/':
        return q
    return x - y * q


def evaluate_line(line):
    """Return None for a blank line, else (ok, text) where text is the value or an error message."""
    if line.strip() == '':
        return None
    try:
        tree = _Parser(line).parse_top()
    except _SyntaxErr as e:
        return False, "error: syntax at %d" % e.col
    try:
        return True, str(_eval(tree))
    except _DivZero:
        return False, "error: division by zero"


def main():
    data = sys.stdin.read()
    all_ok = True
    out = []
    for raw in data.splitlines():
        res = evaluate_line(raw)
        if res is None:
            continue
        ok, text = res
        if not ok:
            all_ok = False
        out.append(text)
    if out:
        sys.stdout.write("\n".join(out) + "\n")
    return 0 if all_ok else 1


def test_precedence_and_parens():
    assert evaluate_line("1 + 2 * 3") == (True, "7")
    assert evaluate_line("(1+2)*3") == (True, "9")
    assert evaluate_line("-(4 - 10) % 4") == (True, "2")


def test_left_associativity():
    assert evaluate_line("8-3-2") == (True, "3")
    assert evaluate_line("2*3%4") == (True, "2")


def test_truncating_division_and_remainder():
    assert evaluate_line("-7/2") == (True, "-3")
    assert evaluate_line("-7%2") == (True, "-1")
    assert evaluate_line("7%-2") == (True, "1")


def test_syntax_error_columns():
    assert evaluate_line("2 *") == (False, "error: syntax at 4")
    assert evaluate_line("1 2") == (False, "error: syntax at 3")
    assert evaluate_line("(1") == (False, "error: syntax at 3")


def test_division_by_zero_and_syntax_priority():
    assert evaluate_line("7 / (3 - 3)") == (False, "error: division by zero")
    assert evaluate_line("1/0 +") == (False, "error: syntax at 6")


def test_blank_line_prints_nothing():
    assert evaluate_line("   ") is None


if __name__ == "__main__":
    sys.exit(main())
