import sys
import threading


class JsonError(Exception):
    def __init__(self, pos):
        super().__init__(pos)
        self.pos = pos


WS = frozenset((0x20, 0x09, 0x0A, 0x0D))

# escape letter -> decoded character code
ESC_DECODE = {
    0x22: 0x22,  # \"
    0x5C: 0x5C,  # \\
    0x2F: 0x2F,  # \/
    0x62: 0x08,  # \b
    0x66: 0x0C,  # \f
    0x6E: 0x0A,  # \n
    0x72: 0x0D,  # \r
    0x74: 0x09,  # \t
}

# character code -> output form for characters that need escaping
OUT_ESC = {
    0x22: b'\\"',
    0x5C: b'\\\\',
    0x08: b'\\b',
    0x0C: b'\\f',
    0x0A: b'\\n',
    0x0D: b'\\r',
    0x09: b'\\t',
}


def hex_value(c):
    if 0x30 <= c <= 0x39:
        return c - 0x30
    if 0x61 <= c <= 0x66:
        return c - 0x61 + 10
    if 0x41 <= c <= 0x46:
        return c - 0x41 + 10
    return -1


def escape_code(v):
    """Output bytes for one character code v (v < 0x80, or a raw input byte)."""
    s = OUT_ESC.get(v)
    if s is not None:
        return s
    if v < 0x20:
        return ('\\u%04x' % v).encode('ascii')
    return bytes((v,))


class _Parser:
    def __init__(self, data):
        self.d = data
        self.n = len(data)
        self.p = 0

    def peek(self):
        return self.d[self.p] if self.p < self.n else -1

    def skip_ws(self):
        d, n, p = self.d, self.n, self.p
        while p < n and d[p] in WS:
            p += 1
        self.p = p

    def value(self):
        self.skip_ws()
        c = self.peek()
        if c == 0x7B:
            return self.obj()
        if c == 0x5B:
            return self.arr()
        if c == 0x22:
            return ('lit', b'"' + self.string() + b'"')
        if c == 0x74:
            return self.keyword(b'true')
        if c == 0x66:
            return self.keyword(b'false')
        if c == 0x6E:
            return self.keyword(b'null')
        if c == 0x2D or (0x30 <= c <= 0x39):
            return ('lit', self.number())
        raise JsonError(self.p)

    def keyword(self, word):
        for i, ch in enumerate(word):
            q = self.p + i
            if q >= self.n or self.d[q] != ch:
                raise JsonError(q)
        self.p += len(word)
        return ('lit', word)

    def number(self):
        d, n = self.d, self.n
        start = p = self.p
        if d[p] == 0x2D:
            p += 1
            if p >= n or not (0x30 <= d[p] <= 0x39):
                raise JsonError(p)
        if d[p] == 0x30:
            p += 1
        else:
            while p < n and 0x30 <= d[p] <= 0x39:
                p += 1
        self.p = p
        return d[start:p]

    def string(self):
        """Parses a string starting at self.p; returns its escaped content (no quotes)."""
        d, n = self.d, self.n
        p = self.p + 1
        out = bytearray()
        while True:
            if p >= n:
                raise JsonError(n)
            c = d[p]
            if c == 0x22:
                p += 1
                break
            if c < 0x20:
                raise JsonError(p)
            if c == 0x5C:
                p += 1
                if p >= n:
                    raise JsonError(n)
                e = d[p]
                if e in ESC_DECODE:
                    out += escape_code(ESC_DECODE[e])
                    p += 1
                elif e == 0x75:  # u
                    p += 1
                    v = 0
                    for _ in range(4):
                        if p >= n:
                            raise JsonError(n)
                        h = hex_value(d[p])
                        if h < 0:
                            raise JsonError(p)
                        v = v * 16 + h
                        p += 1
                    if v < 0x80:
                        out += escape_code(v)
                    else:
                        out += ('\\u%04x' % v).encode('ascii')
                else:
                    raise JsonError(p)
            else:
                out += escape_code(c)
                p += 1
        self.p = p
        return bytes(out)

    def arr(self):
        self.p += 1
        items = []
        self.skip_ws()
        if self.peek() == 0x5D:
            self.p += 1
            return ('arr', items)
        while True:
            items.append(self.value())
            self.skip_ws()
            c = self.peek()
            if c == 0x2C:
                self.p += 1
            elif c == 0x5D:
                self.p += 1
                return ('arr', items)
            else:
                raise JsonError(self.p)

    def obj(self):
        self.p += 1
        members = []
        self.skip_ws()
        if self.peek() == 0x7D:
            self.p += 1
            return ('obj', members)
        while True:
            self.skip_ws()
            if self.peek() != 0x22:
                raise JsonError(self.p)
            key = self.string()
            self.skip_ws()
            if self.peek() != 0x3A:
                raise JsonError(self.p)
            self.p += 1
            members.append((key, self.value()))
            self.skip_ws()
            c = self.peek()
            if c == 0x2C:
                self.p += 1
            elif c == 0x7D:
                self.p += 1
                return ('obj', members)
            else:
                raise JsonError(self.p)


def _fmt(node, depth, out):
    kind, payload = node
    if kind == 'lit':
        out += payload
        return
    inner = b'  ' * (depth + 1)
    last = len(payload) - 1
    if kind == 'arr':
        if not payload:
            out += b'[]'
            return
        out += b'[\n'
        for i, item in enumerate(payload):
            out += inner
            _fmt(item, depth + 1, out)
            if i < last:
                out += b','
            out += b'\n'
        out += b'  ' * depth + b']'
    else:  # obj
        if not payload:
            out += b'{}'
            return
        out += b'{\n'
        for i, (key, val) in enumerate(payload):
            out += inner + b'"' + key + b'": '
            _fmt(val, depth + 1, out)
            if i < last:
                out += b','
            out += b'\n'
        out += b'  ' * depth + b'}'


def format_json(data):
    """Validates and pretty-prints; returns bytes. Raises JsonError on invalid input."""
    parser = _Parser(data)
    parser.skip_ws()
    root = parser.value()
    parser.skip_ws()
    if parser.p < parser.n:
        raise JsonError(parser.p)
    out = bytearray()
    _fmt(root, 0, out)
    out += b'\n'
    return bytes(out)


def locate(data, pos):
    line = data.count(b'\n', 0, pos) + 1
    col = pos - data.rfind(b'\n', 0, pos)
    return line, col


def error_position(data):
    try:
        format_json(data)
    except JsonError as e:
        return locate(data, e.pos)
    return None


def test_format_example():
    src = b'{"a":[1,2,{}],"b":"xA\\n"}'
    expected = b'{\n  "a": [\n    1,\n    2,\n    {}\n  ],\n  "b": "xA\\n"\n}\n'
    assert format_json(src) == expected


def test_string_escapes():
    src = b'"\\u0041\\u00e9\\/\\u0001\\t\\u001F"'
    expected = b'"A\\u00e9/\\u0001\\t\\u001f"\n'
    assert format_json(src) == expected


def test_error_positions():
    assert error_position(b'[1,\n x]') == (2, 2)
    assert error_position(b'[1') == (1, 3)
    assert error_position(b'') == (1, 1)
    assert error_position(b'"a\x01"') == (1, 3)
    assert error_position(b'01') == (1, 2)
    assert error_position(b'{"a":1}') is None


def main():
    data = sys.stdin.buffer.read()
    try:
        out = format_json(data)
    except JsonError as e:
        line, col = locate(data, e.pos)
        sys.stdout.write('error: line %d col %d\n' % (line, col))
        sys.stdout.flush()
        return 1
    sys.stdout.buffer.write(out)
    sys.stdout.buffer.flush()
    return 0


_RESULT = [1]


def _thread_main():
    _RESULT[0] = main()


if __name__ == '__main__':
    sys.setrecursionlimit(1000000)
    try:
        threading.stack_size(256 * 1024 * 1024)
    except (ValueError, RuntimeError):
        pass
    t = threading.Thread(target=_thread_main)
    t.start()
    t.join()
    sys.exit(_RESULT[0])
