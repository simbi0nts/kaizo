#!/usr/bin/env python3
"""csvsum: group and sum a CSV file read from standard input."""
import os
import re
import sys

USAGE = "usage: csvsum <group-column> <sum-column>"

_UNQUOTED = re.compile(rb'[^,"\n]*')
_INT = re.compile(rb'-?[0-9]+')


class BadQuoting(Exception):
    pass


def iter_records(data):
    """Yield records (lists of bytes fields). Raises BadQuoting for the
    record currently being parsed if its quoting is invalid."""
    i = 0
    n = len(data)
    while i < n:
        fields = []
        while True:
            if i < n and data[i] == 34:  # quoted field
                parts = []
                j = i + 1
                while True:
                    k = data.find(b'"', j)
                    if k == -1:
                        raise BadQuoting()
                    if k + 1 < n and data[k + 1] == 34:
                        parts.append(data[j:k + 1])
                        j = k + 2
                        continue
                    parts.append(data[j:k])
                    i = k + 1
                    break
                field = b"".join(parts)
            else:
                m = _UNQUOTED.match(data, i)
                e = m.end()
                field = data[i:e]
                i = e
            fields.append(field)
            if i >= n:
                break
            c = data[i]
            if c == 44:  # ','
                i += 1
                continue
            if c == 10:  # '\n'
                i += 1
                break
            raise BadQuoting()
        yield fields


def format_group(value):
    if b"," in value or b'"' in value or b"\n" in value:
        return b'"' + value.replace(b'"', b'""') + b'"'
    return value


def run(args, data):
    """Pure logic: returns (output_bytes, exit_code)."""
    if len(args) != 2:
        return (USAGE + "\n").encode(), 2
    if not data:
        return b"error: no header\n", 1
    gen = iter_records(data)
    recno = 1
    try:
        header = next(gen)
    except BadQuoting:
        return b"error: record 1\n", 1
    idx = []
    for name in args:
        b = os.fsencode(name) if isinstance(name, str) else name
        if b not in header:
            return b"error: no column " + b + b"\n", 1
        idx.append(header.index(b))
    gi, si = idx
    width = len(header)
    sums = {}
    while True:
        recno += 1
        try:
            rec = next(gen)
        except StopIteration:
            break
        except BadQuoting:
            return ("error: record %d\n" % recno).encode(), 1
        if len(rec) != width:
            return ("error: record %d\n" % recno).encode(), 1
        v = rec[si]
        if not _INT.fullmatch(v):
            return ("error: record %d\n" % recno).encode(), 1
        g = rec[gi]
        sums[g] = sums.get(g, 0) + int(v)
    out = []
    for g in sorted(sums):
        out.append(format_group(g) + b"," + str(sums[g]).encode() + b"\n")
    return b"".join(out), 0


def main():
    args = sys.argv[1:]
    if len(args) != 2:
        sys.stdout.write(USAGE + "\n")
        sys.stdout.flush()
        sys.exit(2)
    data = sys.stdin.buffer.read()
    out, code = run(args, data)
    sys.stdout.buffer.write(out)
    sys.stdout.buffer.flush()
    sys.exit(code)


# ---------------- tests ----------------

def test_parse_quoted():
    data = b'a,"b,""c""\nd",e\nx,,\n'
    recs = list(iter_records(data))
    assert recs == [[b"a", b'b,"c"\nd', b"e"], [b"x", b"", b""]]


def test_format_group():
    assert format_group(b"Oslo") == b"Oslo"
    assert format_group(b"Rome, IT") == b'"Rome, IT"'
    assert format_group(b'a"b') == b'"a""b"'
    assert format_group(b"a\nb") == b'"a\nb"'


def test_example():
    data = (b'city,amount,note\nOslo,10,first\n"Rome, IT",5,"says ""hi"""\n'
            b'Oslo,-3,\n')
    out, code = run(["city", "amount"], data)
    assert code == 0
    assert out == b'Oslo,7\n"Rome, IT",5\n'


def test_errors():
    assert run(["a"], b"") == ((USAGE + "\n").encode(), 2)
    assert run(["a", "b"], b"") == (b"error: no header\n", 1)
    assert run(["x", "y"], b"a,b\n") == (b"error: no column x\n", 1)
    assert run(["a", "y"], b"a,b\n") == (b"error: no column y\n", 1)
    assert run(["a", "b"], b"a,b\n1,2\n1,x\n") == (b"error: record 3\n", 1)
    assert run(["a", "b"], b"a,b\n1,2,3\n") == (b"error: record 2\n", 1)
    assert run(["a", "b"], b'a,b\n"q"x,2\n') == (b"error: record 2\n", 1)
    assert run(["a", "b"], b'a,b\nk,1\n"open,2\nz,3\n') == (b"error: record 3\n", 1)
    assert run(["a", "b"], b'a,b\nk,+1\n') == (b"error: record 2\n", 1)
    assert run(["a", "b"], b"a,b\n") == (b"", 0)
    assert run(["a", "b"], b"a,b\nk,1\nk,2") == (b"k,3\n", 0)


if __name__ == "__main__":
    main()
