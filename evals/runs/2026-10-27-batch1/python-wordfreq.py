#!/usr/bin/env python3
import re
import sys

_WORD_RE = re.compile(rb"[A-Za-z]+")


def count_words(data):
    """Count case-insensitive ASCII-letter words in a bytes object."""
    counts = {}
    for m in _WORD_RE.finditer(data):
        w = m.group(0).lower().decode("ascii")
        counts[w] = counts.get(w, 0) + 1
    return counts


def top_words(counts, n=10):
    """Return list of (count, word) sorted by count desc, then word ascending."""
    items = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
    return [(c, w) for w, c in items[:n]]


def format_lines(entries):
    return "".join("%d %s\n" % (c, w) for c, w in entries)


def main(argv):
    if len(argv) < 2:
        sys.stdout.write("usage: wordfreq <file>\n")
        return 2
    path = argv[1]
    try:
        with open(path, "rb") as f:
            data = f.read()
    except Exception:
        sys.stdout.write("error: cannot read %s\n" % path)
        return 1
    sys.stdout.write(format_lines(top_words(count_words(data))))
    return 0


# ---------------- tests ----------------

def test_example():
    data = b"The cat and the hat. The cat sat!\nA hat, a cat; THE END.\n"
    out = format_lines(top_words(count_words(data)))
    assert out == "4 the\n3 cat\n2 a\n2 hat\n1 and\n1 end\n1 sat\n"


def test_separators():
    c = count_words(b"don't x-ray abc123def caf\xc3\xa9")
    assert c == {"don": 1, "t": 1, "x": 1, "ray": 1, "abc": 1, "def": 1, "caf": 1}


def test_empty_and_no_letters():
    assert top_words(count_words(b"")) == []
    assert top_words(count_words(b"123 !!! \n\t 456")) == []


def test_ties_and_limit():
    data = b" ".join(bytes([ord("a") + i]) for i in range(26))
    entries = top_words(count_words(data))
    assert len(entries) == 10
    assert [w for _, w in entries] == list("abcdefghij")
    assert all(c == 1 for c, _ in entries)


def test_case_insensitive():
    assert count_words(b"Word WORD word wOrD") == {"word": 4}


if __name__ == "__main__":
    sys.exit(main(sys.argv))
