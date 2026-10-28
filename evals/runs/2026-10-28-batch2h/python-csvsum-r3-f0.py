import re
import sys

USAGE = "usage: csvsum <group-column> <sum-column>"
INT_RE = re.compile(r"-?[0-9]+")


def parse_record(s, i):
    """Parse one record starting at index i.

    Returns (fields, next_index), or (None, None) if the record is malformed
    (bad quoting or an unclosed quote).
    """
    n = len(s)
    fields = []
    while True:
        if i < n and s[i] == '"':
            parts = []
            j = i + 1
            while True:
                k = s.find('"', j)
                if k == -1:
                    return None, None  # quote never closed
                parts.append(s[j:k])
                if k + 1 < n and s[k + 1] == '"':
                    parts.append('"')
                    j = k + 2
                else:
                    j = k + 1
                    break
            fields.append("".join(parts))
            i = j
            if i < n and s[i] != "," and s[i] != "\n":
                return None, None  # garbage after closing quote
        else:
            j = i
            while j < n and s[j] != "," and s[j] != "\n":
                if s[j] == '"':
                    return None, None  # quote inside unquoted field
                j += 1
            fields.append(s[i:j])
            i = j
        if i < n and s[i] == ",":
            i += 1
            continue
        # end of record: newline or end of input
        if i < n:
            i += 1
        return fields, i


def quote_field(g):
    if "," in g or '"' in g or "\n" in g:
        return '"' + g.replace('"', '""') + '"'
    return g


def process(s, group, sumcol):
    """Return (exit_code, output_text) for the CSV text s."""
    if s == "":
        return 1, "error: no header\n"
    header, i = parse_record(s, 0)
    if header is None:
        return 1, "error: record 1\n"
    if group not in header:
        return 1, "error: no column " + group + "\n"
    if sumcol not in header:
        return 1, "error: no column " + sumcol + "\n"
    gi = header.index(group)
    si = header.index(sumcol)
    width = len(header)
    n = len(s)
    totals = {}
    recno = 1
    while i < n:
        recno += 1
        fields, i = parse_record(s, i)
        if fields is None or len(fields) != width or not INT_RE.fullmatch(fields[si]):
            return 1, "error: record %d\n" % recno
        g = fields[gi]
        totals[g] = totals.get(g, 0) + int(fields[si])
    lines = []
    for g in sorted(totals, key=lambda x: x.encode("utf-8", "surrogateescape")):
        lines.append("%s,%d\n" % (quote_field(g), totals[g]))
    return 0, "".join(lines)


def emit(text):
    sys.stdout.buffer.write(text.encode("utf-8", "surrogateescape"))
    sys.stdout.buffer.flush()


def main(argv):
    if len(argv) != 3:
        emit(USAGE + "\n")
        return 2
    data = sys.stdin.buffer.read()
    s = data.decode("utf-8", "surrogateescape")
    code, out = process(s, argv[1], argv[2])
    emit(out)
    return code


def test_parse_quoted_fields():
    text = '"a,b","c""d"\n'
    fields, nxt = parse_record(text, 0)
    assert fields == ["a,b", 'c"d']
    assert nxt == len(text)


def test_parse_bad_quoting():
    assert parse_record('"abc', 0) == (None, None)
    assert parse_record('"a"b,c\n', 0) == (None, None)
    assert parse_record('ab"c,d\n', 0) == (None, None)


def test_process_example():
    s = 'city,amount,note\nOslo,10,first\n"Rome, IT",5,"says ""hi"""\nOslo,-3,\n'
    code, out = process(s, "city", "amount")
    assert code == 0
    assert out == 'Oslo,7\n"Rome, IT",5\n'


def test_process_errors():
    assert process("", "a", "b") == (1, "error: no header\n")
    assert process("a,b\n1,x\n", "a", "b") == (1, "error: record 2\n")
    assert process("a,b\n1,2,3\n", "a", "b") == (1, "error: record 2\n")
    assert process("a,b\n1,2\n", "z", "b") == (1, "error: no column z\n")
    assert process("a,b\n", "a", "b") == (0, "")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
