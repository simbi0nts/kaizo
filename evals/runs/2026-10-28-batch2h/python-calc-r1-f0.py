import sys

WS = " \t\r\f\v"


class CalcError(Exception):
    """kind is 'syntax' (value = 1-based column) or 'div0'."""

    def __init__(self, kind, value=None):
        super().__init__(kind)
        self.kind = kind
        self.value = value


class _Parser:
    def __init__(self, text):
        self.s = text
        self.n = len(text)
        self.i = 0

    def skip(self):
        while self.i < self.n and self.s[self.i] in WS:
            self.i += 1

    def peek(self):
        self.skip()
        return self.s[self.i] if self.i < self.n else None

    def fail(self):
        # Column of the first character that cannot continue (1-based).
        # At end of line this is len + 1.
        self.skip()
        raise CalcError("syntax", self.i + 1)

    def parse_expr(self):
        node = self.parse_term()
        while True:
            c = self.peek()
            if c in ("+", "-"):
                self.i += 1
                rhs = self.parse_term()
                node = (c, node, rhs)
            else:
                return node

    def parse_term(self):
        node = self.parse_unary()
        while True:
            c = self.peek()
            if c in ("*", "/", "%"):
                self.i += 1
                rhs = self.parse_unary()
                node = (c, node, rhs)
            else:
                return node

    def parse_unary(self):
        c = self.peek()
        if c == "-":
            self.i += 1
            return ("neg", self.parse_unary())
        return self.parse_primary()

    def parse_primary(self):
        c = self.peek()
        if c is not None and "0" <= c <= "9":
            start = self.i
            while self.i < self.n and "0" <= self.s[self.i] <= "9":
                self.i += 1
            return ("num", int(self.s[start:self.i]))
        if c == "(":
            self.i += 1
            node = self.parse_expr()
            if self.peek() != ")":
                self.fail()
            self.i += 1
            return node
        self.fail()


def parse_line(text):
    p = _Parser(text)
    node = p.parse_expr()
    if p.peek() is not None:
        p.fail()
    return node


def _trunc_div(a, b):
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


def evaluate(node):
    tag = node[0]
    if tag == "num":
        return node[1]
    if tag == "neg":
        return -evaluate(node[1])
    op, left, right = node
    a = evaluate(left)
    b = evaluate(right)
    if op == "+":
        return a + b
    if op == "-":
        return a - b
    if op == "*":
        return a * b
    if b == 0:
        raise CalcError("div0")
    if op == "/":
        return _trunc_div(a, b)
    # op == "%": remainder takes the sign of the dividend (C semantics)
    return a - b * _trunc_div(a, b)


def run_line(text):
    """Return (output_text_or_None, success_bool) for one input line."""
    if text.strip(WS) == "":
        return None, True
    try:
        value = evaluate(parse_line(text))
    except CalcError as e:
        if e.kind == "syntax":
            return "error: syntax at %d" % e.value, False
        return "error: division by zero", False
    return str(value), True


def main():
    sys.setrecursionlimit(10000)
    ok = True
    for raw in sys.stdin:
        out, good = run_line(raw.rstrip("\r\n"))
        if out is not None:
            print(out)
        if not good:
            ok = False
    return 0 if ok else 1


def test_precedence_and_parens():
    assert run_line("1 + 2 * 3") == ("7", True)
    assert run_line("(1+2)*3") == ("9", True)
    assert run_line("-(4 - 10) % 4") == ("2", True)


def test_associativity():
    assert run_line("8-3-2") == ("3", True)
    assert run_line("2*3%4") == ("2", True)
    assert run_line("64/4/2") == ("8", True)


def test_truncation_toward_zero():
    assert run_line("-7/2") == ("-3", True)
    assert run_line("-7%2") == ("-1", True)
    assert run_line("7%-2") == ("1", True)


def test_syntax_and_division_errors():
    assert run_line("2 *") == ("error: syntax at 4", False)
    assert run_line("1 2") == ("error: syntax at 3", False)
    assert run_line("(1") == ("error: syntax at 3", False)
    assert run_line("1/0)") == ("error: syntax at 4", False)
    assert run_line("7 / (3 - 3)") == ("error: division by zero", False)
    # Syntax errors take precedence over division by zero.
    assert run_line("1/0 +") == ("error: syntax at 6", False)


def test_blank_line_prints_nothing():
    assert run_line("   ") == (None, True)
    assert run_line("") == (None, True)


if __name__ == "__main__":
    sys.exit(main())
