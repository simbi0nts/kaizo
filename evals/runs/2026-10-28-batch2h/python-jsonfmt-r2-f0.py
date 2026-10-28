import sys
import threading

WS = b' \t\r\n'
HEX = b'0123456789abcdefABCDEF'
SIMPLE_ESC = {
    ord('"'): 0x22,
    ord('\\'): 0x5c,
    ord('/'): 0x2f,
    ord('b'): 0x08,
    ord('f'): 0x0c,
    ord('n'): 0x0a,
    ord('r'): 0x0d,
    ord('t'): 0x09,
}


class JsonError(Exception):
    def __init__(self, pos):
        Exception.__init__(self, pos)
        self.pos = pos


def esc_byte(c):
    if c == 0x22:
        return b'\\"'
    if c == 0x5c:
        return b'\\\\'
    if c == 0x08:
        return b'\\b'
    if c == 0x0c:
        return b'\\f'
    if c == 0x0a:
        return b'\\n'
    if c == 0x0d:
        return b'\\r'
    if c == 0x09:
        return b'\\t'
    if c < 0x20:
        return b'\\u%04x' % c
    return bytes((c,))


class Parser:
    def __init__(self, data):
        self.data = data
        self.n = len(data)
        self.pos = 0

    def fail(self):
        raise JsonError(self.pos)

    def skip_ws(self):
        data, n, pos = self.data, self.n, self.pos
        while pos < n and data[pos] in WS:
            pos += 1
        self.pos = pos

    def parse_document(self):
        self.skip_ws()
        value = self.parse_value()
        self.skip_ws()
        if self.pos < self.n:
            self.fail()
        return value

    def parse_value(self):
        if self.pos >= self.n:
            self.fail()
        c = self.data[self.pos]
        if c == 0x7b:
            return self.parse_object()
        if c == 0x5b:
            return self.parse_array()
        if c == 0x22:
            return ('lit', self.parse_string())
        if c == 0x2d or 0x30 <= c <= 0x39:
            return ('lit', self.parse_number())
        if c == ord('n'):
            return self.parse_word(b'null')
        if c == ord('t'):
            return self.parse_word(b'true')
        if c == ord('f'):
            return self.parse_word(b'false')
        self.fail()

    def parse_word(self, word):
        for ch in word:
            if self.pos >= self.n:
                self.fail()
            if self.data[self.pos] != ch:
                self.fail()
            self.pos += 1
        return ('lit', word)

    def parse_number(self):
        data, n = self.data, self.n
        start = self.pos
        pos = self.pos
        if data[pos] == 0x2d:
            pos += 1
        if pos >= n:
            self.pos = pos
            self.fail()
        c = data[pos]
        if c == 0x30:
            pos += 1
        elif 0x31 <= c <= 0x39:
            while pos < n and 0x30 <= data[pos] <= 0x39:
                pos += 1
        else:
            self.pos = pos
            self.fail()
        self.pos = pos
        return data[start:pos]

    def parse_string(self):
        # Returns the string already re-escaped for output, including quotes.
        data, n = self.data, self.n
        pos = self.pos + 1
        out = [b'"']
        while True:
            if pos >= n:
                self.pos = n
                self.fail()
            c = data[pos]
            if c == 0x22:
                pos += 1
                break
            if c == 0x5c:
                pos += 1
                if pos >= n:
                    self.pos = n
                    self.fail()
                e = data[pos]
                if e in SIMPLE_ESC:
                    out.append(esc_byte(SIMPLE_ESC[e]))
                    pos += 1
                elif e == 0x75:  # 'u'
                    v = 0
                    for k in range(1, 5):
                        q = pos + k
                        if q >= n:
                            self.pos = n
                            self.fail()
                        h = data[q]
                        if h not in HEX:
                            self.pos = q
                            self.fail()
                        v = v * 16 + int(chr(h), 16)
                    pos += 5
                    if v < 0x80:
                        out.append(esc_byte(v))
                    else:
                        out.append(b'\\u%04x' % v)
                else:
                    self.pos = pos
                    self.fail()
            elif c < 0x20:
                self.pos = pos
                self.fail()
            else:
                start = pos
                while pos < n and data[pos] >= 0x20 and data[pos] != 0x22 and data[pos] != 0x5c:
                    pos += 1
                out.append(data[start:pos])
        self.pos = pos
        out.append(b'"')
        return b''.join(out)

    def parse_array(self):
        self.pos += 1
        self.skip_ws()
        items = []
        if self.pos < self.n and self.data[self.pos] == 0x5d:
            self.pos += 1
            return ('arr', items)
        while True:
            items.append(self.parse_value())
            self.skip_ws()
            if self.pos >= self.n:
                self.fail()
            c = self.data[self.pos]
            self.pos += 1
            if c == 0x5d:
                return ('arr', items)
            if c != 0x2c:
                self.pos -= 1
                self.fail()
            self.skip_ws()

    def parse_object(self):
        self.pos += 1
        self.skip_ws()
        members = []
        if self.pos < self.n and self.data[self.pos] == 0x7d:
            self.pos += 1
            return ('obj', members)
        while True:
            if self.pos >= self.n or self.data[self.pos] != 0x22:
                self.fail()
            key = self.parse_string()
            self.skip_ws()
            if self.pos >= self.n or self.data[self.pos] != 0x3a:
                self.fail()
            self.pos += 1
            self.skip_ws()
            value = self.parse_value()
            members.append((key, value))
            self.skip_ws()
            if self.pos >= self.n:
                self.fail()
            c = self.data[self.pos]
            if c == 0x7d:
                self.pos += 1
                return ('obj', members)
            if c != 0x2c:
                self.fail()
            self.pos += 1
            self.skip_ws()


def format_value(v, depth):
    kind = v[0]
    if kind == 'lit':
        return v[1]
    ind = b'  ' * (depth + 1)
    close = b'  ' * depth
    if kind == 'arr':
        if not v[1]:
            return b'[]'
        parts = [ind + format_value(x, depth + 1) for x in v[1]]
        return b'[\n' + b',\n'.join(parts) + b'\n' + close + b']'
    if not v[1]:
        return b'{}'
    parts = [ind + k + b': ' + format_value(x, depth + 1) for k, x in v[1]]
    return b'{\n' + b',\n'.join(parts) + b'\n' + close + b'}'


def run(data):
    """Returns (exit_code, output_bytes)."""
    try:
        value = Parser(data).parse_document()
    except JsonError as err:
        pos = err.pos
        line = data.count(b'\n', 0, pos) + 1
        start = data.rfind(b'\n', 0, pos) + 1
        col = pos - start + 1
        return 1, ('error: line %d col %d\n' % (line, col)).encode('ascii')
    return 0, format_value(value, 0) + b'\n'


def main():
    data = sys.stdin.buffer.read()
    result = {}

    def target():
        result['r'] = run(data)

    sys.setrecursionlimit(1000000)
    try:
        threading.stack_size(256 * 1024 * 1024)
    except (ValueError, RuntimeError):
        pass
    t = threading.Thread(target=target)
    t.start()
    t.join()
    if 'r' not in result:
        sys.exit(2)
    code, out = result['r']
    sys.stdout.buffer.write(out)
    sys.stdout.flush()
    sys.exit(code)


def test_format_example():
    data = b'{"a":[1,2,{}],"b":"xA\\n"}'
    code, out = run(data)
    assert code == 0
    assert out == b'{\n  "a": [\n    1,\n    2,\n    {}\n  ],\n  "b": "xA\\n"\n}\n'


def test_escapes():
    data = b'"\\u0041\\u00e9\\/\\u0001"'
    code, out = run(data)
    assert code == 0
    assert out == b'"A\\u00e9/\\u0001"\n'


def test_empty_containers_and_scalars():
    assert run(b' [ ] ') == (0, b'[]\n')
    assert run(b'{}') == (0, b'{}\n')
    assert run(b'-0') == (0, b'-0\n')
    assert run(b'null') == (0, b'null\n')


def test_error_positions():
    assert run(b'[1,]') == (1, b'error: line 1 col 4\n')
    assert run(b'{"a" 1}') == (1, b'error: line 1 col 6\n')
    assert run(b'"a\n"') == (1, b'error: line 1 col 3\n')
    assert run(b'[1,\n') == (1, b'error: line 2 col 1\n')
    assert run(b'01') == (1, b'error: line 1 col 2\n')


if __name__ == '__main__':
    main()
