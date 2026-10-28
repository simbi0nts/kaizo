#!/usr/bin/env python3
"""csvsum: group and sum a CSV read from standard input.

Usage: csvsum <group-column> <sum-column>
"""
import re
import sys

USAGE = "usage: csvsum <group-column> <sum-column>"
INT_RE = re.compile(r"-?[0-9]+")


def parse_record(text, i):
    """Parse one record starting at index i.

    Returns (fields, next_index, ok). When ok is False the record is malformed
    and fields is None.
    """
    n = len(text)
    fields = []
    while True:
        if i < n and text[i] == '"':
            i += 1
            parts = []
            while True:
                j = text.find('"', i)
                if j == -1:
                    # Quote never closed: the record is bad.
                    return None, n, False
                parts.append(text[i:j])
                if j + 1 < n and text[j + 1] == '"':
                    parts.append('"')
                    i = j + 2
                else:
                    i = j + 1
                    break
            if i < n and text[i] not in ",\n":
                return None, i, False
            fields.append("".join(parts))
        else:
            j = i
            while j < n and text[j] not in ",\n\"":
                j += 1
            if j < n and text[j] == '"':
                # Quote inside an unquoted field.
                return None, j, False
            fields.append(text[i:j])
            i = j
        if i >= n:
            return fields, n, True
        if text[i] == ",":
            i += 1
            continue
        # Newline ends the record.
        return fields, i + 1, True


def quote_group(value):
    if "," in value or '"' in value or "\n" in value:
        return '"' + value.replace('"', '""') + '"'
    return value


def sort_key(s):
    return s.encode("utf-8", "surrogateescape")


def run(text, group, sum_col):
    """Return (exit_code, output_text) for the given CSV text."""
    if text == "":
        return 1, "error: no header\n"
    header, pos, ok = parse_record(text, 0)
    if not ok:
        return 1, "error: record 1\n"
    for name in (group, sum_col):
        if name not in header:
            return 1, "error: no column " + name + "\n"
    gi = header.index(group)
    si = header.index(sum_col)
    width = len(header)
    n = len(text)
    totals = {}
    recno = 1
    while pos < n:
        recno += 1
        fields, pos, ok = parse_record(text, pos)
        if not ok or len(fields) != width or not INT_RE.fullmatch(fields[si]):
            return 1, "error: record %d\n" % recno
        key = fields[gi]
        totals[key] = totals.get(key, 0) + int(fields[si])
    out = []
    for key in sorted(totals, key=sort_key):
        out.append("%s,%d\n" % (quote_group(key), totals[key]))
    return 0, "".join(out)


def main():
    args = sys.argv[1:]
    if len(args) != 2:
        sys.stdout.write(USAGE + "\n")
        sys.stdout.flush()
        return 2
    data = sys.stdin.buffer.read().decode("utf-8", "surrogateescape")
    code, out = run(data, args[0], args[1])
    sys.stdout.buffer.write(out.encode("utf-8", "surrogateescape"))
    sys.stdout.flush()
    return code


def test_parse_plain():
    assert parse_record("a,b\nc,d\n", 0) == (["a", "b"], 4, True)


def test_parse_quoted():
    text = '"x, ""y""",\n"multi\nline",2'
    fields, pos, ok = parse_record(text, 0)
    assert ok and fields == ['x, "y"', ""]
    fields, pos, ok = parse_record(text, pos)
    assert ok and fields == ["multi\nline", "2"] and pos == len(text)


def test_parse_errors():
    assert not parse_record('"abc', 0)[2]
    assert not parse_record('"a"b,c\n', 0)[2]
    assert not parse_record('a"b,c\n', 0)[2]


def test_run_example():
    text = 'city,amount,note\nOslo,10,first\n"Rome, IT",5,"says ""hi"""\nOslo,-3,\n'
    code, out = run(text, "city", "amount")
    assert code == 0
    assert out == 'Oslo,7\n"Rome, IT",5\n'


def test_run_errors():
    assert run("", "a", "b") == (1, "error: no header\n")
    assert run("a,b\n1,2\n3\n", "a", "b") == (1, "error: record 3\n")
    assert run("a,b\n1,2\n", "a", "z") == (1, "error: no column z\n")
    assert run("a,b\n1,x\n", "a", "b") == (1, "error: record 2\n")


if __name__ == "__main__":
    sys.exit(main())
