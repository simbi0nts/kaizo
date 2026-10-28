import sys

WS = b" \t\n\r"
HEX = b"0123456789abcdefABCDEF"
SIMPLE_ESC = {
    0x22: b'\\"',
    0x5C: b"\\\\",
    0x2F: b"/",
    0x62: b"\\b",
    0x66: b"\\f",
    0x6E: b"\\n",
    0x72: b"\\r",
    0x74: b"\\t",
}


class JsonError(Exception):
    def __init__(self, pos):
        super().__init__(pos)
        self.pos = pos


def escape_ascii(v):
    """Re-escape an ASCII code point (below 0x80) per the output rules."""
    if v == 0x22:
        return b'\\"'
    if v == 0x5C:
        return b"\\\\"
    if v == 0x08:
        return b"\\b"
    if v == 0x0C:
        return b"\\f"
    if v == 0x0A:
        return b"\\n"
    if v == 0x0D:
        return b"\\r"
    if v == 0x09:
        return b"\\t"
    if v < 0x20:
        return b"\\u%04x" % v
    return bytes([v])


class Parser:
    def __init__(self, data):
        self.d = data
        self.n = len(data)
        self.i = 0

    def fail(self, pos=None):
        raise JsonError(self.i if pos is None else pos)

    def skip_ws(self):
        d, n, i = self.d, self.n, self.i
        while i < n and d[i] in WS:
            i += 1
        self.i = i

    def peek(self):
        return self.d[self.i] if self.i < self.n else None

    def parse_document(self):
        self.skip_ws()
        node = self.parse_value()
        self.skip_ws()
        if self.i < self.n:
            self.fail()
        return node

    def parse_value(self):
        c = self.peek()
        if c is None:
            self.fail()
        if c == 0x7B:
            return self.parse_object()
        if c == 0x5B:
            return self.parse_array()
        if c == 0x22:
            return ("val", self.parse_string())
        if c == 0x2D or 0x30 <= c <= 0x39:
            return ("val", self.parse_number())
        if c == ord("t"):
            return ("val", self.parse_literal(b"true"))
        if c == ord("f"):
            return ("val", self.parse_literal(b"false"))
        if c == ord("n"):
            return ("val", self.parse_literal(b"null"))
        self.fail()

    def parse_literal(self, word):
        for ch in word:
            if self.i >= self.n or self.d[self.i] != ch:
                self.fail()
            self.i += 1
        return word

    def parse_number(self):
        d, n = self.d, self.n
        start = i = self.i
        if i < n and d[i] == 0x2D:
            i += 1
        if i >= n:
            self.i = i
            self.fail()
        c = d[i]
        if c == 0x30:
            i += 1
        elif 0x31 <= c <= 0x39:
            while i < n and 0x30 <= d[i] <= 0x39:
                i += 1
        else:
            self.i = i
            self.fail()
        self.i = i
        return d[start:i]

    def parse_string(self):
        """Parse a string at self.i (the opening quote); return its re-escaped bytes with quotes."""
        d, n = self.d, self.n
        i = self.i + 1
        out = bytearray(b'"')
        while True:
            if i >= n:
                self.i = i
                self.fail()
            c = d[i]
            if c == 0x22:
                out.append(0x22)
                i += 1
                break
            if c < 0x20:
                self.i = i
                self.fail()
            if c != 0x5C:
                out.append(c)
                i += 1
                continue
            # escape sequence
            i += 1
            if i >= n:
                self.i = i
                self.fail()
            e = d[i]
            if e in SIMPLE_ESC:
                out += SIMPLE_ESC[e]
                i += 1
            elif e == 0x75:  # 'u'
                i += 1
                v = 0
                for _ in range(4):
                    if i >= n or d[i] not in HEX:
                        self.i = i
                        self.fail()
                    v = v * 16 + int(chr(d[i]), 16)
                    i += 1
                if v < 0x80:
                    out += escape_ascii(v)
                else:
                    out += b"\\u%04x" % v
            else:
                self.i = i
                self.fail()
        self.i = i
        return bytes(out)

    def parse_array(self):
        self.i += 1
        items = []
        self.skip_ws()
        if self.peek() == 0x5D:
            self.i += 1
            return ("arr", items)
        while True:
            self.skip_ws()
            items.append(self.parse_value())
            self.skip_ws()
            c = self.peek()
            if c == 0x2C:
                self.i += 1
                continue
            if c == 0x5D:
                self.i += 1
                return ("arr", items)
            self.fail()

    def parse_object(self):
        self.i += 1
        members = []
        self.skip_ws()
        if self.peek() == 0x7D:
            self.i += 1
            return ("obj", members)
        while True:
            self.skip_ws()
            if self.peek() != 0x22:
                self.fail()
            key = self.parse_string()
            self.skip_ws()
            if self.peek() != 0x3A:
                self.fail()
            self.i += 1
            self.skip_ws()
            value = self.parse_value()
            members.append((key, value))
            self.skip_ws()
            c = self.peek()
            if c == 0x2C:
                self.i += 1
                continue
            if c == 0x7D:
                self.i += 1
                return ("obj", members)
            self.fail()


def emit(node, depth, out):
    kind = node[0]
    if kind == "val":
        out += node[1]
    elif kind == "arr":
        items = node[1]
        if not items:
            out += b"[]"
            return
        out += b"[\n"
        ind = b"  " * (depth + 1)
        last = len(items) - 1
        for k, item in enumerate(items):
            out += ind
            emit(item, depth + 1, out)
            if k < last:
                out += b","
            out += b"\n"
        out += b"  " * depth + b"]"
    else:  # obj
        members = node[1]
        if not members:
            out += b"{}"
            return
        out += b"{\n"
        ind = b"  " * (depth + 1)
        last = len(members) - 1
        for k, (key, value) in enumerate(members):
            out += ind + key + b": "
            emit(value, depth + 1, out)
            if k < last:
                out += b","
            out += b"\n"
        out += b"  " * depth + b"}"


def format_document(data):
    node = Parser(data).parse_document()
    out = bytearray()
    emit(node, 0, out)
    out += b"\n"
    return bytes(out)


def error_message(data, pos):
    line = data.count(b"\n", 0, pos) + 1
    last_nl = data.rfind(b"\n", 0, pos)
    col = pos - last_nl
    return "error: line %d col %d" % (line, col)


def main():
    sys.setrecursionlimit(100000)
    data = sys.stdin.buffer.read()
    try:
        result = format_document(data)
    except JsonError as e:
        sys.stdout.write(error_message(data, e.pos) + "\n")
        sys.stdout.flush()
        return 1
    sys.stdout.buffer.write(result)
    sys.stdout.buffer.flush()
    return 0


# ---------------- unit tests ----------------

def _fmt(text):
    return format_document(text.encode("latin-1")).decode("latin-1")


def _err(text):
    data = text.encode("latin-1")
    try:
        format_document(data)
    except JsonError as e:
        return error_message(data, e.pos)
    return None


def test_example_document():
    src = '{"a":[1,2,{}],"b":"xA\\n"}'
    expected = '{\n  "a": [\n    1,\n    2,\n    {}\n  ],\n  "b": "xA\\n"\n}\n'
    assert _fmt(src) == expected


def test_empty_containers_and_nesting():
    assert _fmt("[]") == "[]\n"
    assert _fmt(' {"k":[{}]} ') == '{\n  "k": [\n    {}\n  ]\n}\n'


def test_escapes_and_unicode():
    assert _fmt('"\\u0041\\u00e9\\/\\t"') == '"A\\u00e9/\\t"\n'
    assert _fmt('"\\u0001\\u0022"') == '"\\u0001\\""\n'


def test_error_positions():
    assert _err("[1,]") == "error: line 1 col 4"
    assert _err('{\n "a" 1}') == "error: line 2 col 6"
    assert _err("[1") == "error: line 1 col 3"
    assert _err("01") == "error: line 1 col 2"


if __name__ == "__main__":
    sys.exit(main())
