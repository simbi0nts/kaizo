#!/usr/bin/env python3
"""csvsum: group and sum a CSV file read from standard input."""
import re
import sys

USAGE = "usage: csvsum <group-column> <sum-column>"
_SEP = re.compile(r"[,\n]")
_INT = re.compile(r"-?[0-9]+")


def parse_records(text):
    """Yield each record as a list of fields; yield None for a bad record and stop."""
    n = len(text)
    if n == 0:
        return
    i = 0
    while True:
        fields = []
        finished = False  # end of input reached
        while True:
            if i < n and text[i] == '"':
                j = i + 1
                buf = []
                while True:
                    k = text.find('"', j)
                    if k < 0:
                        yield None
                        return
                    if k + 1 < n and text[k + 1] == '"':
                        buf.append(text[j:k + 1])
                        j = k + 2
                        continue
                    buf.append(text[j:k])
                    i = k + 1
                    break
                fields.append("".join(buf))
                if i >= n:
                    finished = True
                    break
                c = text[i]
                if c == ",":
                    i += 1
                    continue
                if c == "\n":
                    i += 1
                    break
                yield None
                return
            else:
                m = _SEP.search(text, i)
                if m is None:
                    field = text[i:]
                    i = n
                    if '"' in field:
                        yield None
                        return
                    fields.append(field)
                    finished = True
                    break
                k = m.start()
                field = text[i:k]
                if '"' in field:
                    yield None
                    return
                fields.append(field)
                i = k + 1
                if text[k] == ",":
                    continue
                break
        yield fields
        if finished or i >= n:
            return


def quote_field(s):
    if "," in s or '"' in s or "\n" in s:
        return '"' + s.replace('"', '""') + '"'
    return s


def _bkey(s):
    return s.encode("utf-8", "surrogateescape")


def run(text, args):
    """Return (output_text, exit_code)."""
    if len(args) != 2:
        return USAGE + "\n", 2
    group_col, sum_col = args
    gen = parse_records(text)
    header = next(gen, False)
    if header is False:
        return "error: no header\n", 1
    if header is None:
        return "error: record 1\n", 1
    for name in (group_col, sum_col):
        if name not in header:
            return "error: no column %s\n" % name, 1
    gi = header.index(group_col)
    si = header.index(sum_col)
    width = len(header)
    sums = {}
    recno = 1
    for rec in gen:
        recno += 1
        if rec is None or len(rec) != width:
            return "error: record %d\n" % recno, 1
        v = rec[si]
        if not _INT.fullmatch(v):
            return "error: record %d\n" % recno, 1
        g = rec[gi]
        sums[g] = sums.get(g, 0) + int(v)
    out = []
    for g in sorted(sums, key=_bkey):
        out.append("%s,%d\n" % (quote_field(g), sums[g]))
    return "".join(out), 0


def main():
    data = sys.stdin.buffer.read()
    text = data.decode("utf-8", "surrogateescape")
    out, code = run(text, sys.argv[1:])
    sys.stdout.buffer.write(out.encode("utf-8", "surrogateescape"))
    sys.stdout.flush()
    sys.exit(code)


# ---------------- tests ----------------

def test_example():
    text = 'city,amount,note\nOslo,10,first\n"Rome, IT",5,"says ""hi"""\nOslo,-3,\n'
    assert run(text, ["city", "amount"]) == ('Oslo,7\n"Rome, IT",5\n', 0)


def test_parse_quoted_newline_and_no_trailing_newline():
    recs = list(parse_records('a,b\n"x\ny",1\n"q""",2'))
    assert recs == [["a", "b"], ["x\ny", "1"], ['q"', "2"]]


def test_errors():
    assert run("", ["a", "b"]) == ("error: no header\n", 1)
    assert run("a,b\n", ["c", "d"]) == ("error: no column c\n", 1)
    assert run("a,b\n", ["a", "d"]) == ("error: no column d\n", 1)
    assert run("a,b\nx,1\nx,1.5\n", ["a", "b"]) == ("error: record 3\n", 1)
    assert run("a,b\nx,1,2\n", ["a", "b"]) == ("error: record 2\n", 1)
    assert run('a,b\nx,1\n"x,1\n', ["a", "b"]) == ("error: record 3\n", 1)
    assert run('a,b\n"x"y,1\n', ["a", "b"]) == ("error: record 2\n", 1)
    assert run('a,b\nx"y,1\n', ["a", "b"]) == ("error: record 2\n", 1)
    assert run("a,b\n", ["a"]) == (USAGE + "\n", 2)


def test_quote_and_sort():
    assert quote_field('a"b') == '"a""b"'
    assert quote_field("plain") == "plain"
    text = 'g,v\nb,1\nB,2\n"a\nz",3\n'
    assert run(text, ["g", "v"]) == ('B,2\n"a\nz",3\nb,1\n', 0)


def test_header_only():
    assert run("a,b\n", ["a", "b"]) == ("", 0)
    assert run("a,b", ["b", "a"]) == ("", 0)


if __name__ == "__main__":
    main()
