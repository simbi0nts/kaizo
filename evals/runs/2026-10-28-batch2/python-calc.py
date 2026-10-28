import sys


class CalcSyntaxError(Exception):
    def __init__(self, col):
        super().__init__("syntax at %d" % col)
        self.col = col


class CalcDivZero(Exception):
    pass


class Parser:
    def __init__(self, text):
        self.s = text
        self.n = len(text)
        self.i = 0

    def skip(self):
        while self.i < self.n and self.s[self.i] in " \t\r\n\f\v":
            self.i += 1

    def peek(self):
        self.skip()
        if self.i < self.n:
            return self.s[self.i]
        return None

    def fail(self):
        self.skip()
        raise CalcSyntaxError(self.i + 1)

    def parse(self):
        node = self.expr()
        if self.peek() is not None:
            self.fail()
        return node

    def expr(self):
        node = self.term()
        while True:
            c = self.peek()
            if c in ("+", "-"):
                self.i += 1
                rhs = self.term()
                node = (c, node, rhs)
            else:
                return node

    def term(self):
        node = self.unary()
        while True:
            c = self.peek()
            if c in ("*", "/", "%"):
                self.i += 1
                rhs = self.unary()
                node = (c, node, rhs)
            else:
                return node

    def unary(self):
        negs = 0
        while self.peek() == "-":
            self.i += 1
            negs += 1
        node = self.primary()
        for _ in range(negs):
            node = ("neg", node)
        return node

    def primary(self):
        c = self.peek()
        if c is not None and "0" <= c <= "9":
            start = self.i
            while self.i < self.n and "0" <= self.s[self.i] <= "9":
                self.i += 1
            return ("num", int(self.s[start:self.i]))
        if c == "(":
            self.i += 1
            node = self.expr()
            if self.peek() != ")":
                self.fail()
            self.i += 1
            return node
        self.fail()


def trunc_div(a, b):
    if b == 0:
        raise CalcDivZero()
    q = abs(a) // abs(b)
    if (a < 0) != (b < 0):
        q = -q
    return q


def trunc_mod(a, b):
    if b == 0:
        raise CalcDivZero()
    return a - b * trunc_div(a, b)


def evaluate(node):
    # iterative post-order evaluation to avoid deep recursion
    stack = [(node, False)]
    vals = []
    while stack:
        nd, done = stack.pop()
        kind = nd[0]
        if kind == "num":
            vals.append(nd[1])
            continue
        if kind == "neg":
            if done:
                vals.append(-vals.pop())
            else:
                stack.append((nd, True))
                stack.append((nd[1], False))
            continue
        if done:
            b = vals.pop()
            a = vals.pop()
            if kind == "+":
                vals.append(a + b)
            elif kind == "-":
                vals.append(a - b)
            elif kind == "*":
                vals.append(a * b)
            elif kind == "/":
                vals.append(trunc_div(a, b))
            else:
                vals.append(trunc_mod(a, b))
        else:
            stack.append((nd, True))
            stack.append((nd[2], False))
            stack.append((nd[1], False))
    return vals[0]


def calc_line(line):
    """Return (output_line or None, ok)."""
    line = line.rstrip("\n").rstrip("\r") if line.endswith("\n") else line.rstrip("\r")
    if line.strip() == "":
        return None, True
    try:
        tree = Parser(line).parse()
    except CalcSyntaxError as e:
        return "error: syntax at %d" % e.col, False
    try:
        return str(evaluate(tree)), True
    except CalcDivZero:
        return "error: division by zero", False


def main():
    sys.setrecursionlimit(1000000)
    ok_all = True
    out = []
    for line in sys.stdin:
        res, ok = calc_line(line)
        if res is not None:
            out.append(res)
        if not ok:
            ok_all = False
    if out:
        sys.stdout.write("\n".join(out) + "\n")
    sys.stdout.flush()
    return 0 if ok_all else 1


def test_precedence_and_assoc():
    assert calc_line("1 + 2 * 3")[0] == "7"
    assert calc_line("(1+2)*3")[0] == "9"
    assert calc_line("8-3-2")[0] == "3"
    assert calc_line("2*3%4")[0] == "2"
    assert calc_line("-(4 - 10) % 4")[0] == "2"
    assert calc_line("--3")[0] == "3"


def test_truncating_division():
    assert calc_line("-7/2")[0] == "-3"
    assert calc_line("-7%2")[0] == "-1"
    assert calc_line("7%-2")[0] == "1"
    assert calc_line("7 / (3 - 3)") == ("error: division by zero", False)
    assert calc_line("1 % 0")[0] == "error: division by zero"


def test_syntax_errors():
    assert calc_line("2 *") == ("error: syntax at 4", False)
    assert calc_line("1 2")[0] == "error: syntax at 3"
    assert calc_line("(1")[0] == "error: syntax at 3"
    assert calc_line("1/0 +")[0] == "error: syntax at 6"
    assert calc_line(")")[0] == "error: syntax at 1"
    assert calc_line("1 + a")[0] == "error: syntax at 5"


def test_empty_lines():
    assert calc_line("") == (None, True)
    assert calc_line("   \n") == (None, True)


if __name__ == "__main__":
    sys.exit(main())
