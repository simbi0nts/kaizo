import sys
import re
import threading

WS = re.compile(rb'[ \t\n\r]*')
PLAIN = re.compile(rb'[^"\\\x00-\x1f]+')
INT = re.compile(rb'-?(?:0|[1-9][0-9]*)')
HEX = b'0123456789abcdefABCDEF'
LITS = {0x74: b'true', 0x66: b'false', 0x6e: b'null'}
SIMPLE_ESC = {0x22: b'\\"', 0x5c: b'\\\\', 0x2f: b'/', 0x62: b'\\b',
              0x66: b'\\f', 0x6e: b'\\n', 0x72: b'\\r', 0x74: b'\\t'}


class JErr(Exception):
    def __init__(self, pos):
        Exception.__init__(self, pos)
        self.pos = pos


def esc_char(v):
    """Output form of a character with code v < 0x80."""
    if v == 0x22:
        return b'\\"'
    if v == 0x5c:
        return b'\\\\'
    if v == 8:
        return b'\\b'
    if v == 12:
        return b'\\f'
    if v == 10:
        return b'\\n'
    if v == 13:
        return b'\\r'
    if v == 9:
        return b'\\t'
    if v < 0x20:
        return b'\\u00' + ('%02x' % v).encode()
    return bytes([v])


class Parser:
    def __init__(self, d):
        self.d = d
        self.n = len(d)

    def ws(self, i):
        return WS.match(self.d, i).end()

    def value(self, i):
        d, n = self.d, self.n
        if i >= n:
            raise JErr(n)
        c = d[i]
        if c == 0x7b:
            return self.obj(i)
        if c == 0x5b:
            return self.arr(i)
        if c == 0x22:
            return self.string(i)
        if c in LITS:
            lit = LITS[c]
            for k in range(len(lit)):
                if i + k >= n:
                    raise JErr(n)
                if d[i + k] != lit[k]:
                    raise JErr(i + k)
            return lit, i + len(lit)
        if c == 0x2d or 0x30 <= c <= 0x39:
            m = INT.match(d, i)
            if not m:
                raise JErr(i + 1)
            return m.group(), m.end()
        raise JErr(i)

    def string(self, i):
        d, n = self.d, self.n
        i += 1
        out = [b'"']
        while True:
            m = PLAIN.match(d, i)
            if m:
                out.append(m.group())
                i = m.end()
            if i >= n:
                raise JErr(n)
            c = d[i]
            if c == 0x22:
                out.append(b'"')
                return b''.join(out), i + 1
            if c == 0x5c:
                i += 1
                if i >= n:
                    raise JErr(n)
                e = d[i]
                if e in SIMPLE_ESC:
                    out.append(SIMPLE_ESC[e])
                    i += 1
                elif e == 0x75:
                    h = i + 1
                    for k in range(4):
                        if h + k >= n:
                            raise JErr(n)
                        if d[h + k] not in HEX:
                            raise JErr(h + k)
                    hx = d[h:h + 4]
                    v = int(hx, 16)
                    if v < 0x80:
                        out.append(esc_char(v))
                    else:
                        out.append(b'\\u' + hx.lower())
                    i = h + 4
                else:
                    raise JErr(i)
            else:
                raise JErr(i)

    def arr(self, i):
        d, n = self.d, self.n
        i = self.ws(i + 1)
        items = []
        if i < n and d[i] == 0x5d:
            return ('a', items), i + 1
        while True:
            v, i = self.value(i)
            items.append(v)
            i = self.ws(i)
            if i >= n:
                raise JErr(n)
            c = d[i]
            if c == 0x2c:
                i = self.ws(i + 1)
                continue
            if c == 0x5d:
                return ('a', items), i + 1
            raise JErr(i)

    def obj(self, i):
        d, n = self.d, self.n
        i = self.ws(i + 1)
        items = []
        if i < n and d[i] == 0x7d:
            return ('o', items), i + 1
        while True:
            if i >= n:
                raise JErr(n)
            if d[i] != 0x22:
                raise JErr(i)
            k, i = self.string(i)
            i = self.ws(i)
            if i >= n:
                raise JErr(n)
            if d[i] != 0x3a:
                raise JErr(i)
            i = self.ws(i + 1)
            v, i = self.value(i)
            items.append((k, v))
            i = self.ws(i)
            if i >= n:
                raise JErr(n)
            c = d[i]
            if c == 0x2c:
                i = self.ws(i + 1)
                continue
            if c == 0x7d:
                return ('o', items), i + 1
            raise JErr(i)


def parse(d):
    p = Parser(d)
    i = p.ws(0)
    v, i = p.value(i)
    i = p.ws(i)
    if i < p.n:
        raise JErr(i)
    return v


def ser(v, ind, out):
    if isinstance(v, bytes):
        out.append(v)
        return
    tag, items = v
    if not items:
        out.append(b'[]' if tag == 'a' else b'{}')
        return
    out.append(b'[\n' if tag == 'a' else b'{\n')
    pad = b'  ' * (ind + 1)
    last = len(items) - 1
    for idx, it in enumerate(items):
        out.append(pad)
        if tag == 'o':
            out.append(it[0])
            out.append(b': ')
            ser(it[1], ind + 1, out)
        else:
            ser(it, ind + 1, out)
        out.append(b',\n' if idx < last else b'\n')
    out.append(b'  ' * ind + (b']' if tag == 'a' else b'}'))


def format_doc(d):
    v = parse(d)
    out = []
    ser(v, 0, out)
    out.append(b'\n')
    return b''.join(out)


def pos_to_lc(d, pos):
    line = d.count(b'\n', 0, pos) + 1
    col = pos - d.rfind(b'\n', 0, pos)
    return line, col


def error_message(d):
    """Return None if valid, else the error message string."""
    try:
        format_doc(d)
        return None
    except JErr as e:
        l, c = pos_to_lc(d, e.pos)
        return 'error: line %d col %d' % (l, c)


def run(result):
    data = sys.stdin.buffer.read()
    try:
        out = format_doc(data)
    except JErr as e:
        l, c = pos_to_lc(data, e.pos)
        sys.stdout.write('error: line %d col %d\n' % (l, c))
        sys.stdout.flush()
        result[0] = 1
        return
    sys.stdout.buffer.write(out)
    sys.stdout.buffer.flush()
    result[0] = 0


def main():
    sys.setrecursionlimit(1000000)
    try:
        threading.stack_size(512 * 1024 * 1024)
    except Exception:
        try:
            threading.stack_size(64 * 1024 * 1024)
        except Exception:
            pass
    result = [1]
    t = threading.Thread(target=run, args=(result,))
    t.start()
    t.join()
    sys.exit(result[0])


# ---------------- tests ----------------

def test_example():
    d = b'{"a":[1,2,{}],"b":"xA\\n"}'
    exp = b'{\n  "a": [\n    1,\n    2,\n    {}\n  ],\n  "b": "xA\\n"\n}\n'
    assert format_doc(d) == exp


def test_escapes():
    assert format_doc(b'"\\u0041\\u00e9\\u00FF\\/\\u001F\\u0022"') == \
        b'"A\\u00e9\\u00ff/\\u001f\\""\n'
    assert format_doc(b'"\xc3\xa9"') == b'"\xc3\xa9"\n'
    assert format_doc(b' [] ') == b'[]\n'
    assert format_doc(b'-0') == b'-0\n'


def test_errors():
    assert error_message(b'') == 'error: line 1 col 1'
    assert error_message(b'[1,]') == 'error: line 1 col 4'
    assert error_message(b'01') == 'error: line 1 col 2'
    assert error_message(b'{"a":1,\n"b" 2}') == 'error: line 2 col 5'
    assert error_message(b'nul') == 'error: line 1 col 4'
    assert error_message(b'nulx') == 'error: line 1 col 4'
    assert error_message(b'"a\x01"') == 'error: line 1 col 3'
    assert error_message(b'"\\x"') == 'error: line 1 col 3'
    assert error_message(b'"\\u12g4"') == 'error: line 1 col 6'
    assert error_message(b'-') == 'error: line 1 col 2'
    assert error_message(b'-a') == 'error: line 1 col 2'
    assert error_message(b'[1 2]') == 'error: line 1 col 4'
    assert error_message(b'{,}') == 'error: line 1 col 2'
    assert error_message(b'1.5') == 'error: line 1 col 2'


def test_deep_nesting():
    sys.setrecursionlimit(100000)
    d = b'[' * 500 + b']' * 500
    assert format_doc(d).count(b'\n') == 999


if __name__ == '__main__':
    main()
