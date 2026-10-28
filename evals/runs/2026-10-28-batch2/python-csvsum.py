#!/usr/bin/env python3
"""csvsum: group and sum a CSV file read from standard input."""
import os
import re
import sys

USAGE = "usage: csvsum <group-column> <sum-column>"

_UNQUOTED = re.compile(rb'[^,"\n]*')
_INT = re.compile(rb'-?[0-9]+')


class CsvError(Exception):
    def __init__(self, message):
        super().__init__(message)
        self.message = message


def parse_records(data):
    """Yield records (lists of bytes fields) from data.

    Yields None for a record with invalid quoting and then stops.
    """
    i = 0
    n = len(data)
    while i < n:
        fields = []
        while True:
            if data[i:i + 1] == b'"':
                i += 1
                buf = bytearray()
                while True:
                    j = data.find(b'"', i)
                    if j < 0:
                        yield None
                        return
                    buf += data[i:j]
                    if j + 1 < n and data[j + 1] == 34:
                        buf += b'"'
                        i = j + 2
                        continue
                    i = j + 1
                    break
                fields.append(bytes(buf))
            else:
                j = _UNQUOTED.match(data, i).end()
                fields.append(data[i:j])
                i = j
            if i >= n:
                yield fields
                return
            c = data[i]
            if c == 44:  # ','
                i += 1
                continue
            if c == 10:  # '\n'
                i += 1
                yield fields
                break
            yield None
            return


def is_integer(value):
    return _INT.fullmatch(value) is not None


def format_group(value):
    if b',' in value or b'"' in value or b'\n' in value:
        return b'"' + value.replace(b'"', b'""') + b'"'
    return value


def csvsum(data, group_name, sum_name):
    """Return output bytes or raise CsvError with the message."""
    records = parse_records(data)
    header = next(records, False)
    if header is False:
        raise CsvError("error: no header")
    if header is None:
        raise CsvError("error: record 1")
    gname = os.fsencode(group_name)
    sname = os.fsencode(sum_name)
    if gname not in header:
        raise CsvError("error: no column " + group_name)
    if sname not in header:
        raise CsvError("error: no column " + sum_name)
    gi = header.index(gname)
    si = header.index(sname)
    width = len(header)
    sums = {}
    num = 1
    for rec in records:
        num += 1
        if rec is None or len(rec) != width or not is_integer(rec[si]):
            raise CsvError("error: record %d" % num)
        key = rec[gi]
        sums[key] = sums.get(key, 0) + int(rec[si])
    out = bytearray()
    for key in sorted(sums):
        out += format_group(key) + b',' + str(sums[key]).encode() + b'\n'
    return bytes(out)


def main(argv):
    if len(argv) != 2:
        print(USAGE)
        return 2
    data = sys.stdin.buffer.read()
    try:
        out = csvsum(data, argv[0], argv[1])
    except CsvError as e:
        print(e.message)
        return 1
    sys.stdout.buffer.write(out)
    sys.stdout.flush()
    return 0


# ---------------- unit tests ----------------

def test_parse_quoted_fields():
    data = b'a,b\n"x, ""y""\nz",1\nlast,2'
    recs = list(parse_records(data))
    assert recs == [[b'a', b'b'], [b'x, "y"\nz', b'1'], [b'last', b'2']]


def test_parse_bad_quoting():
    assert list(parse_records(b'a\n"x"y\n')) == [[b'a'], None]
    assert list(parse_records(b'a\n"open\n')) == [[b'a'], None]
    assert list(parse_records(b'a\nb"c\n')) == [[b'a'], None]


def test_parse_trailing_comma_and_empty():
    assert list(parse_records(b'a,\n')) == [[b'a', b'']]
    assert list(parse_records(b'\n')) == [[b'']]
    assert list(parse_records(b'')) == []


def test_is_integer():
    assert is_integer(b'10')
    assert is_integer(b'-3')
    assert not is_integer(b'')
    assert not is_integer(b'-')
    assert not is_integer(b'+1')
    assert not is_integer(b' 1')
    assert not is_integer(b'1.0')


def test_format_group():
    assert format_group(b'Oslo') == b'Oslo'
    assert format_group(b'Rome, IT') == b'"Rome, IT"'
    assert format_group(b'a"b') == b'"a""b"'
    assert format_group(b'a\nb') == b'"a\nb"'


def test_example():
    data = (b'city,amount,note\nOslo,10,first\n'
            b'"Rome, IT",5,"says ""hi"""\nOslo,-3,\n')
    assert csvsum(data, 'city', 'amount') == b'Oslo,7\n"Rome, IT",5\n'


def test_errors():
    def err(data, g='a', s='b'):
        try:
            csvsum(data, g, s)
        except CsvError as e:
            return e.message
        return None
    assert err(b'') == 'error: no header'
    assert err(b'x,y\n') == 'error: no column a'
    assert err(b'a,y\n') == 'error: no column b'
    assert err(b'a,b\nx,1\nx\n') == 'error: record 3'
    assert err(b'a,b\nx,1\nx,z\n') == 'error: record 3'
    assert err(b'a,b\nx,"1\n') == 'error: record 2'
    assert err(b'a,b\n') is None


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
