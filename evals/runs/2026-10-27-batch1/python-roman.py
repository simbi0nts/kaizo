import re
import sys

PAIRS = [
    (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
    (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
    (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
]
VALUES = {"I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000}


def to_roman(n):
    if not (1 <= n <= 3999):
        raise ValueError("out of range")
    out = []
    for value, sym in PAIRS:
        while n >= value:
            out.append(sym)
            n -= value
    return "".join(out)


def from_roman(s):
    """Return the value of a canonical Roman numeral, or None if invalid."""
    if not re.fullmatch(r"[IVXLCDMivxlcdm]+", s):
        return None
    up = s.upper()
    total = 0
    for i, ch in enumerate(up):
        v = VALUES[ch]
        if i + 1 < len(up) and VALUES[up[i + 1]] > v:
            total -= v
        else:
            total += v
    if not (1 <= total <= 3999):
        return None
    if to_roman(total) != up:
        return None
    return total


def convert(arg):
    """Return (output_line, exit_code)."""
    if re.fullmatch(r"[0-9]+", arg):
        n = int(arg)
        if 1 <= n <= 3999:
            return to_roman(n), 0
        return "error: invalid input " + arg, 1
    v = from_roman(arg)
    if v is not None:
        return str(v), 0
    return "error: invalid input " + arg, 1


def main(argv):
    if len(argv) != 1:
        print("usage: roman <number|numeral>")
        return 2
    out, code = convert(argv[0])
    print(out)
    return code


def test_to_roman():
    assert to_roman(1994) == "MCMXCIV"
    assert to_roman(4) == "IV"
    assert to_roman(3999) == "MMMCMXCIX"
    assert to_roman(1) == "I"


def test_from_roman_canonical():
    assert from_roman("mcmxciv") == 1994
    assert from_roman("MMMCMXCIX") == 3999
    assert from_roman("IIII") is None
    assert from_roman("VX") is None
    assert from_roman("MMMM") is None
    assert from_roman("abc") is None
    assert from_roman("") is None


def test_convert_errors():
    assert convert("0") == ("error: invalid input 0", 1)
    assert convert("4000") == ("error: invalid input 4000", 1)
    assert convert("-5") == ("error: invalid input -5", 1)
    assert convert("+5") == ("error: invalid input +5", 1)
    assert convert("") == ("error: invalid input ", 1)
    assert convert("1994") == ("MCMXCIV", 0)
    assert convert("xiv") == ("14", 0)


def test_roundtrip():
    for n in range(1, 4000):
        assert from_roman(to_roman(n)) == n
        assert from_roman(to_roman(n).lower()) == n


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
