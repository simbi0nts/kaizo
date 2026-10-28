#!/usr/bin/env python3
"""jsonfmt: validate a JSON document from stdin and pretty-print it."""
import re
import sys

_WS = re.compile(rb'[ \t\n\r]*')
_SPECIAL = re.compile(rb'["\\\x00-\x1f]')
_HEX = b'0123456789abcdefABCDEF'
_DIGITS = b'0123456789'
_SIMPLE_ESC = {
    ord('"'): b'\\"',
    ord('\\'): b'\\\\',
    ord('/'): b'/',
    ord('b'): b'\\b',
    ord('f'): b'\\f',
    ord('n'): b'\\n',
    ord('r'): b'\\r',
    ord('t'): b'\\t',
}


class JsonError(Exception):
    def __init__(self, pos):
        super().__init__(pos)
        self.pos = pos


def escape_char(v):
    if v == 0x22:
        return b'\\"'
    if v == 0x5C:
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


def _skip_ws(data, i):
    return _WS.match(data, i).end()


def _parse_string(data, i, out):
    n = len(data)
    i += 1  # opening quote
    buf = [b'"']
    while True:
        m = _SPECIAL.search(data, i)
        if m is None:
            raise JsonError(n)
        j = m.start()
        if j > i:
            buf.append(data[i:j])
        c = data[j]
        if c == 0x22:
            i = j + 1
            break
        if c < 0x20:
            raise JsonError(j)
        # backslash
        i = j + 1
        if i >= n:
            raise JsonError(n)
        e = data[i]
        if e in _SIMPLE_ESC:
            buf.append(_SIMPLE_ESC[e])
            i += 1
        elif e == ord('u'):
            for k in range(1, 5):
                if i + k >= n:
                    raise JsonError(n)
                if data[i + k] not in _HEX:
                    raise JsonError(i + k)
            hexs = data[i + 1:i + 5]
            v = int(hexs, 16)
            if v < 0x80:
                buf.append(escape_char(v))
            else:
                buf.append(b'\\u' + hexs.lower())
            i += 5
        else:
            raise JsonError(i)
    buf.append(b'"')
    out.append(b''.join(buf))
    return i


def _parse_number(data, i, out):
    n = len(data)
    start = i
    if data[i] == ord('-'):
        i += 1
        if i >= n:
            raise JsonError(n)
        if data[i] not in _DIGITS:
            raise JsonError(i)
    if data[i] == ord('0'):
        i += 1
    else:
        while i < n and data[i] in _DIGITS:
            i += 1
    out.append(data[start:i])
    return i


def _parse_literal(data, i, word, out):
    n = len(data)
    for k in range(len(word)):
        if i + k >= n:
            raise JsonError(n)
        if data[i + k] != word[k]:
            raise JsonError(i + k)
    out.append(word)
    return i + len(word)


def format_json(data):
    """Return pretty-printed bytes, or raise JsonError(pos)."""
    n = len(data)
    out = []
    stack = []
    i = 0
    state = 'value'
    while True:
        if state == 'value':
            i = _skip_ws(data, i)
            if i >= n:
                raise JsonError(n)
            c = data[i]
            if c == ord('['):
                j = _skip_ws(data, i + 1)
                if j < n and data[j] == ord(']'):
                    out.append(b'[]')
                    i = j + 1
                    state = 'after'
                else:
                    stack.append(b'[')
                    out.append(b'[\n' + b'  ' * len(stack))
                    i = j
                    state = 'value'
            elif c == ord('{'):
                j = _skip_ws(data, i + 1)
                if j < n and data[j] == ord('}'):
                    out.append(b'{}')
                    i = j + 1
                    state = 'after'
                else:
                    stack.append(b'{')
                    out.append(b'{\n' + b'  ' * len(stack))
                    i = j
                    state = 'key'
            elif c == ord('"'):
                i = _parse_string(data, i, out)
                state = 'after'
            elif c == ord('-') or c in _DIGITS:
                i = _parse_number(data, i, out)
                state = 'after'
            elif c == ord('t'):
                i = _parse_literal(data, i, b'true', out)
                state = 'after'
            elif c == ord('f'):
                i = _parse_literal(data, i, b'false', out)
                state = 'after'
            elif c == ord('n'):
                i = _parse_literal(data, i, b'null', out)
                state = 'after'
            else:
                raise JsonError(i)
        elif state == 'key':
            i = _skip_ws(data, i)
            if i >= n:
                raise JsonError(n)
            if data[i] != ord('"'):
                raise JsonError(i)
            i = _parse_string(data, i, out)
            i = _skip_ws(data, i)
            if i >= n:
                raise JsonError(n)
            if data[i] != ord(':'):
                raise JsonError(i)
            i += 1
            out.append(b': ')
            state = 'value'
        else:  # after
            i = _skip_ws(data, i)
            if not stack:
                if i < n:
                    raise JsonError(i)
                break
            if i >= n:
                raise JsonError(n)
            c = data[i]
            top = stack[-1]
            if c == ord(','):
                i += 1
                out.append(b',\n' + b'  ' * len(stack))
                state = 'key' if top == b'{' else 'value'
            elif (c == ord(']') and top == b'[') or (c == ord('}') and top == b'{'):
                stack.pop()
                out.append(b'\n' + b'  ' * len(stack) + bytes([c]))
                i += 1
                state = 'after'
            else:
                raise JsonError(i)
    out.append(b'\n')
    return b''.join(out)


def line_col(data, pos):
    line = data.count(b'\n', 0, pos) + 1
    col = pos - (data.rfind(b'\n', 0, pos) + 1) + 1
    return line, col


def main():
    data = sys.stdin.buffer.read()
    try:
        result = format_json(data)
    except JsonError as e:
        line, col = line_col(data, e.pos)
        sys.stdout.write('error: line %d col %d\n' % (line, col))
        sys.stdout.flush()
        return 1
    sys.stdout.buffer.write(result)
    sys.stdout.buffer.flush()
    return 0


def _err(data):
    try:
        format_json(data)
    except JsonError as e:
        return line_col(data, e.pos)
    return None


def test_example():
    src = b'{"a":[1,2,{}],"b":"xA\\n"}'
    expected = b'{\n  "a": [\n    1,\n    2,\n    {}\n  ],\n  "b": "xA\\n"\n}\n'
    assert format_json(src) == expected


def test_escapes():
    src = b'"\\u0041\\u00E9\\/\\u001F\\t"'
    assert format_json(src) == b'"A\\u00e9/\\u001f\\t"\n'


def test_scalars_and_empty():
    assert format_json(b'  null ') == b'null\n'
    assert format_json(b'-0') == b'-0\n'
    assert format_json(b'[ ]') == b'[]\n'
    assert format_json(b'{ }') == b'{}\n'


def test_error_positions():
    assert _err(b'') == (1, 1)
    assert _err(b'[1,]') == (1, 4)
    assert _err(b'[\n  tru') == (2, 6)
    assert _err(b'01') == (1, 2)
    assert _err(b'1.5') == (1, 2)
    assert _err(b'"a\\x"') == (1, 4)
    assert _err(b'"\\u12g4"') == (1, 6)
    assert _err(b'{"a" 1}') == (1, 6)
    assert _err(b'"a\x01"') == (1, 3)
    assert _err(b'-x') == (1, 2)
    assert _err(b'[1] x') == (1, 5)


def test_deep_nesting():
    depth = 5000
    src = b'[' * depth + b']' * depth
    out = format_json(src)
    assert out.endswith(b']\n')


if __name__ == '__main__':
    sys.exit(main())
