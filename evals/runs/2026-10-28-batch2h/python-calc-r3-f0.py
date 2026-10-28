import sys

WS = " \t\r\n\f\v"


class SyntaxErr(Exception):
    def __init__(self, col):
        super().__init__(col)
        self.col = col


class DivZero(Exception):
    pass


def tokenize(line):
    toks = []
    i, n = 0, len(line)
    while i < n:
        c = line[i]
        if c in WS:
            i += 1
        elif "0" <= c <= "9":
            j = i
            while j < n and "0" <= line[j] <= "9":
                j += 1
            toks.append(("num", int(line[i:j]), i + 1))
            i = j
        elif c in "+-*/%()":
            toks.append((c, None, i + 1))
            i += 1
        else:
            toks.append(("bad", c, i + 1))
            break
    toks.append(("end", None, n + 1))
    return toks


class Parser:
    def __init__(self, toks):
        self.toks = toks
        self.pos = 0

    def peek(self):
        return self.toks[self.pos]

    def advance(self):
        tok = self.toks[self.pos]
        self.pos += 1
        return tok

    def parse(self):
        node = self.expr()
        if self.peek()[0] != "end":
            raise SyntaxErr(self.peek()[2])
        return node

    def expr(self):
        node = self.term()
        while self.peek()[0] in ("+", "-"):
            op = self.advance()[0]
            node = ("bin", op, node, self.term())
        return node

    def term(self):
        node = self.unary()
        while self.peek()[0] in ("*", "/", "%"):
            op = self.advance()[0]
            node = ("bin", op, node, self.unary())
        return node

    def unary(self):
        if self.peek()[0] == "-":
            self.advance()
            return ("neg", self.unary())
        return self.primary()

    def primary(self):
        kind, val, col = self.peek()
        if kind == "num":
            self.advance()
            return ("num", val)
        if kind == "(":
            self.advance()
            node = self.expr()
            if self.peek()[0] != ")":
                raise SyntaxErr(self.peek()[2])
            self.advance()
            return node
        raise SyntaxErr(col)


def tdiv(a, b):
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def trem(a, b):
    return a - b * tdiv(a, b)


def evaluate(node):
    kind = node[0]
    if kind == "num":
        return node[1]
    if kind == "neg":
        return -evaluate(node[1])
    _, op, left, right = node
    a = evaluate(left)
    b = evaluate(right)
    if op == "+":
        return a + b
    if op == "-":
        return a - b
    if op == "*":
        return a * b
    if b == 0:
        raise DivZero()
    if op == "/":
        return tdiv(a, b)
    return trem(a, b)


def evaluate_line(line):
    """Return (ok, text) for one expression line."""
    try:
        tree = Parser(tokenize(line)).parse()
    except SyntaxErr as e:
        return False, f"error: syntax at {e.col}"
    try:
        return True, str(evaluate(tree))
    except DivZero:
        return False, "error: division by zero"


def main():
    ok = True
    for raw in sys.stdin:
        line = raw.rstrip("\r\n")
        if line.strip(WS) == "":
            continue
        good, text = evaluate_line(line)
        ok = ok and good
        print(text)
    return 0 if ok else 1


def test_precedence():
    assert evaluate_line("1 + 2 * 3") == (True, "7")
    assert evaluate_line("(1+2)*3") == (True, "9")
    assert evaluate_line("-(4 - 10) % 4") == (True, "2")


def test_associativity_and_signs():
    assert evaluate_line("8-3-2") == (True, "3")
    assert evaluate_line("2*3%4") == (True, "2")
    assert evaluate_line("-7/2") == (True, "-3")
    assert evaluate_line("-7%2") == (True, "-1")
    assert evaluate_line("7%-2") == (True, "1")
    assert evaluate_line("--3") == (True, "3")


def test_errors():
    assert evaluate_line("2 *") == (False, "error: syntax at 4")
    assert evaluate_line("7 / (3 - 3)") == (False, "error: division by zero")
    assert evaluate_line("1 2") == (False, "error: syntax at 3")
    assert evaluate_line("(1") == (False, "error: syntax at 3")
    assert evaluate_line("1 + 2 )") == (False, "error: syntax at 7")
    assert evaluate_line("1/0 +") == (False, "error: syntax at 6")


if __name__ == "__main__":
    sys.exit(main())
