import re
import sys

_INT_RE = re.compile(r'-?[0-9]+')
_UNQUOTED_RE = re.compile(r'[^,"\n]*')


def parse_int(s):
    """Return the integer value of s, or None if s is not an integer per the spec."""
    if _INT_RE.fullmatch(s) is None:
        return None
    try:
        return int(s)
    except ValueError:  # extremely long digit strings
        return None


def parse_record(text, i):
    """Parse one record starting at index i.

    Returns (fields, next_index, ok). ok is False for invalid or unclosed quoting.
    """
    n = len(text)
    fields = []
    while True:
        if i < n and text[i] == '"':
            parts = []
            j = i + 1
            while True:
                k = text.find('"', j)
                if k == -1:
                    return None, n, False  # quote never closed
                parts.append(text[j:k])
                if k + 1 < n and text[k + 1] == '"':
                    parts.append('"')
                    j = k + 2
                    continue
                break
            # k is the closing quote
            fields.append(''.join(parts))
            i = k + 1
            if i < n and text[i] not in ',\n':
                return None, n, False
        else:
            end = _UNQUOTED_RE.match(text, i).end()
            if end < n and text[end] == '"':
                return None, n, False  # quote inside unquoted field
            fields.append(text[i:end])
            i = end
        # now at ',', '\n' or end of text
        if i >= n:
            return fields, n, True
        if text[i] == '\n':
            return fields, i + 1, True
        i += 1  # skip ','


def quote_group(g):
    if any(c in g for c in ',"\n'):
        return '"' + g.replace('"', '""') + '"'
    return g


def csvsum(text, group_name, sum_name):
    """Return (exit_code, stdout_text, stderr_text)."""
    if text == '':
        return 1, '', 'error: no header'

    header, i, ok = parse_record(text, 0)
    if not ok:
        return 1, '', 'error: record 1'

    for name in (group_name, sum_name):
        if name not in header:
            return 1, '', 'error: no column ' + name

    gi = header.index(group_name)
    si = header.index(sum_name)
    width = len(header)
    n = len(text)
    totals = {}
    recno = 1

    while i < n:
        recno += 1
        fields, nxt, ok = parse_record(text, i)
        if not ok or len(fields) != width:
            return 1, '', 'error: record %d' % recno
        value = parse_int(fields[si])
        if value is None:
            return 1, '', 'error: record %d' % recno
        i = nxt
        g = fields[gi]
        totals[g] = totals.get(g, 0) + value

    lines = []
    for g in sorted(totals, key=lambda s: s.encode('utf-8', 'surrogateescape')):
        lines.append('%s,%d\n' % (quote_group(g), totals[g]))
    return 0, ''.join(lines), ''


def main(argv):
    if len(argv) != 2:
        sys.stderr.write('usage: csvsum <group-column> <sum-column>\n')
        return 2
    data = sys.stdin.buffer.read().decode('utf-8', 'surrogateescape')
    code, out, err = csvsum(data, argv[0], argv[1])
    if err:
        sys.stderr.write(err + '\n')
    if out:
        sys.stdout.buffer.write(out.encode('utf-8', 'surrogateescape'))
    sys.stdout.buffer.flush()
    return code


def test_example_from_spec():
    text = ('city,amount,note\n'
            'Oslo,10,first\n'
            '"Rome, IT",5,"says ""hi"""\n'
            'Oslo,-3,\n')
    code, out, err = csvsum(text, 'city', 'amount')
    assert code == 0
    assert out == 'Oslo,7\n"Rome, IT",5\n'
    assert err == ''


def test_quoted_newline_in_group_and_escaped_quotes():
    text = 'a,b\n"x\ny",1\n"q""q",2\n'
    code, out, _ = csvsum(text, 'a', 'b')
    assert code == 0
    assert out == '"q""q",2\n"x\ny",1\n'


def test_bad_record_and_missing_column_and_unclosed_quote():
    code, out, err = csvsum('a,b\n1,x\n', 'a', 'b')
    assert (code, out, err) == (1, '', 'error: record 2')

    code, out, err = csvsum('a,b\n1,2\n', 'z', 'b')
    assert (code, out, err) == (1, '', 'error: no column z')

    code, out, err = csvsum('a,b\n"x,1\n', 'a', 'b')
    assert (code, out, err) == (1, '', 'error: record 2')

    code, out, err = csvsum('', 'a', 'b')
    assert (code, out, err) == (1, '', 'error: no header')


def test_parse_record_quoting_rules():
    fields, nxt, ok = parse_record('"a""b",c,"d\ne"\n', 0)
    assert ok and fields == ['a"b', 'c', 'd\ne'] and nxt == len('"a""b",c,"d\ne"\n')
    _, _, ok = parse_record('"ab"c,1\n', 0)
    assert not ok


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
