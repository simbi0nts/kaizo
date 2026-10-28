#!/usr/bin/env python3
"""jsonfmt: validate a JSON document from stdin and pretty-print it."""
import re
import sys

WS = re.compile(rb'[ \t\n\r]*')
PLAIN = re.compile(rb'[^"\\\x00-\x1f]*')
DIGITS = re.compile(rb'[0-9]*')
HEX = b'0123456789abcdefABCDEF'

SIMPLE_ESC = {
    0x22: b'\\"',
    0x5c: b'\\\\',
    0x2f: b'/',
    0x62: b'\\b',
    0x66: b'\\f',
    0x6e: b'\\n',
    0x72: b'\\r',
    0x74: b'\\t',
}

CHAR_ESC = {0x22: b'\\"', 0x5c: b'\\\\', 8: b'\\b', 12: b'\\f',
            10: b'\\n', 13: b'\\r', 9: b'\\t'}


class JsonError(Exception):
    def __init__(self, pos):
        super().__init__(pos)
        self.pos = pos


def esc_char(v):
    if v in CHAR_ESC:
        return CHAR_ESC[v]
    if v < 0x20:
        return b'\\u00' + ('%02x' % v).encode()
    return bytes([v])


def position(data, pos):
    line = data.count(b'\n', 0, pos) + 1
    col = pos - (data.rfind(b'\n', 0, pos) + 1) + 1
    return line, col


def parse_string(data, pos, out):
    n = len(data)
    p = pos + 1
    parts = [b'"']
    while True:
        m = PLAIN.match(data, p)
        e = m.end()
        if e > p:
            parts.append(data[p:e])
        p = e
        if p >= n:
            raise JsonError(n)
        c = data[p]
        if c == 0x22:
            parts.append(b'"')
            out.append(b''.join(parts))
            return p + 1
        if c < 0x20:
            raise JsonError(p)
        # backslash
        if p + 1 >= n:
            raise JsonError(n)
        e = data[p + 1]
        if e in SIMPLE_ESC:
            parts.append(SIMPLE_ESC[e])
            p += 2
        elif e == 0x75:  # u
            for k in range(2, 6):
                q = p + k
                if q >= n:
                    raise JsonError(n)
                if data[q] not in HEX:
                    raise JsonError(q)
            hx = data[p + 2:p + 6]
            v = int(hx, 16)
            if v < 0x80:
                parts.append(esc_char(v))
            else:
                parts.append(b'\\u' + hx.lower())
            p += 6
        else:
            raise JsonError(p + 1)


def parse_number(data, pos, out):
    n = len(data)
    start = pos
    if data[pos] == 0x2d:
        pos += 1
        if pos >= n:
            raise JsonError(n)
        if not (0x30 <= data[pos] <= 0x39):
            raise JsonError(pos)
    if data[pos] == 0x30:
        pos += 1
    else:
        pos = DIGITS.match(data, pos + 1).end()
    out.append(data[start:pos])
    return pos


LITERALS = {0x74: b'true', 0x66: b'false', 0x6e: b'null'}


def format_json(data):
    n = len(data)
    out = []
    stack = []
    pos = WS.match(data, 0).end()
    mode = 'value'
    while True:
        if mode == 'value':
            if pos >= n:
                raise JsonError(n)
            c = data[pos]
            if c == 0x7b or c == 0x5b:
                close = c + 2
                p = WS.match(data, pos + 1).end()
                if p < n and data[p] == close:
                    out.append(bytes([c, close]))
                    pos = p + 1
                    mode = 'after'
                else:
                    out.append(bytes([c]) + b'\n')
                    stack.append(close)
                    pos = p
                    if c == 0x5b:
                        out.append(b'  ' * len(stack))
                        mode = 'value'
                    else:
                        mode = 'key'
            elif c == 0x22:
                pos = parse_string(data, pos, out)
                mode = 'after'
            elif c == 0x2d or 0x30 <= c <= 0x39:
                pos = parse_number(data, pos, out)
                mode = 'after'
            elif c in LITERALS:
                lit = LITERALS[c]
                for i, ch in enumerate(lit):
                    q = pos + i
                    if q >= n:
                        raise JsonError(n)
                    if data[q] != ch:
                        raise JsonError(q)
                out.append(lit)
                pos += len(lit)
                mode = 'after'
            else:
                raise JsonError(pos)
        elif mode == 'key':
            if pos >= n:
                raise JsonError(n)
            if data[pos] != 0x22:
                raise JsonError(pos)
            out.append(b'  ' * len(stack))
            pos = parse_string(data, pos, out)
            pos = WS.match(data, pos).end()
            if pos >= n:
                raise JsonError(n)
            if data[pos] != 0x3a:
                raise JsonError(pos)
            out.append(b': ')
            pos = WS.match(data, pos + 1).end()
            mode = 'value'
        else:  # after a value
            pos = WS.match(data, pos).end()
            if not stack:
                if pos < n:
                    raise JsonError(pos)
                break
            if pos >= n:
                raise JsonError(n)
            c = data[pos]
            if c == 0x2c:
                out.append(b',\n')
                pos = WS.match(data, pos + 1).end()
                if stack[-1] == 0x5d:
                    out.append(b'  ' * len(stack))
                    mode = 'value'
                else:
                    mode = 'key'
            elif c == stack[-1]:
                out.append(b'\n' + b'  ' * (len(stack) - 1) + bytes([c]))
                stack.pop()
                pos += 1
            else:
                raise JsonError(pos)
    out.append(b'\n')
    return b''.join(out)


def main():
    data = sys.stdin.buffer.read()
    try:
        result = format_json(data)
    except JsonError as e:
        line, col = position(data, e.pos)
        sys.stdout.write('error: line %d col %d\n' % (line, col))
        sys.stdout.flush()
        sys.exit(1)
    sys.stdout.buffer.write(result)
    sys.stdout.flush()
    sys.exit(0)


# ---------------- tests ----------------

def _err(doc):
    try:
        format_json(doc)
    except JsonError as e:
        return position(doc, e.pos)
    return None


def test_example():
    doc = b'{"a":[1,2,{}],"b":"x\\u0041\\n"}'
    expected = (b'{\n  "a": [\n    1,\n    2,\n    {}\n  ],\n'
                b'  "b": "xA\\n"\n}\n')
    assert format_json(doc) == expected


def test_scalars_and_empty():
    assert format_json(b' null ') == b'null\n'
    assert format_json(b'-0') == b'-0\n'
    assert format_json(b'[ ]') == b'[]\n'
    assert format_json(b'{\n}') == b'{}\n'
    assert format_json(b'[[1]]') == b'[\n  [\n    1\n  ]\n]\n'


def test_string_escapes():
    assert format_json(b'"\\/\\u001F\\u00e9\\u00C9\\u0022"') == \
        b'"/\\u001f\\u00e9\\u00c9\\""\n'
    assert format_json(b'"\xc3\xa9"') == b'"\xc3\xa9"\n'


def test_errors():
    assert _err(b'') == (1, 1)
    assert _err(b'[1,]') == (1, 4)
    assert _err(b'01') == (1, 2)
    assert _err(b'[1,\n') == (2, 1)
    assert _err(b'nul') == (1, 4)
    assert _err(b'nulx') == (1, 4)
    assert _err(b'"a\nb"') == (1, 3)
    assert _err(b'"\\x"') == (1, 3)
    assert _err(b'"\\u12g4"') == (1, 6)
    assert _err(b'{"a" 1}') == (1, 6)
    assert _err(b'{1:2}') == (1, 2)
    assert _err(b'-a') == (1, 2)
    assert _err(b'1.5') == (1, 2)
    assert _err(b'[1}') == (1, 3)
    assert _err(b'{} x') == (1, 4)


def test_deep_nesting():
    depth = 5000
    doc = b'[' * depth + b']' * depth
    out = format_json(doc)
    assert out.endswith(b']\n')


if __name__ == '__main__':
    main()
