#!/usr/bin/env python3
"""Conway's Game of Life on a finite grid."""
import sys

USAGE = "usage: life <generations>"
BAD_GRID = "error: bad grid"


class GridError(Exception):
    pass


def parse_generations(args):
    """Return generation count from argv[1:], or None if invalid."""
    if len(args) != 1:
        return None
    s = args[0].strip()
    if not s or not all(c in "0123456789" for c in s):
        return None
    return int(s)


def parse_grid(text):
    """Parse text into a list of lists of bools. Raises GridError."""
    lines = text.split("\n")
    lines = [ln[:-1] if ln.endswith("\r") else ln for ln in lines]
    while lines and lines[-1] == "":
        lines.pop()
    if not lines:
        return []
    width = len(lines[0])
    grid = []
    for ln in lines:
        if len(ln) != width:
            raise GridError()
        row = []
        for c in ln:
            if c == "#":
                row.append(True)
            elif c == ".":
                row.append(False)
            else:
                raise GridError()
        grid.append(row)
    return grid


def step(grid):
    """Compute one generation; cells outside the grid are dead."""
    h = len(grid)
    if h == 0:
        return []
    w = len(grid[0])
    new = []
    for r in range(h):
        row = []
        for c in range(w):
            n = 0
            for dr in (-1, 0, 1):
                rr = r + dr
                if rr < 0 or rr >= h:
                    continue
                gr = grid[rr]
                for dc in (-1, 0, 1):
                    if dr == 0 and dc == 0:
                        continue
                    cc = c + dc
                    if 0 <= cc < w and gr[cc]:
                        n += 1
            if grid[r][c]:
                row.append(n == 2 or n == 3)
            else:
                row.append(n == 3)
        new.append(row)
    return new


def run(grid, generations):
    for _ in range(generations):
        grid = step(grid)
    return grid


def count_alive(grid):
    return sum(sum(1 for c in row if c) for row in grid)


def render(grid):
    lines = ["".join("#" if c else "." for c in row) for row in grid]
    lines.append("alive: %d" % count_alive(grid))
    return "\n".join(lines) + "\n"


def main(argv):
    gens = parse_generations(argv[1:])
    if gens is None:
        sys.stdout.write(USAGE + "\n")
        return 2
    text = sys.stdin.read()
    try:
        grid = parse_grid(text)
    except GridError:
        sys.stdout.write(BAD_GRID + "\n")
        return 1
    grid = run(grid, gens)
    sys.stdout.write(render(grid))
    return 0


# ---------------- tests ----------------

def test_blinker():
    g = parse_grid(".....\n..#..\n..#..\n..#..\n.....\n")
    out = render(run(g, 1))
    assert out == ".....\n.....\n.###.\n.....\n.....\nalive: 3\n"
    assert render(run(g, 2)) == render(g)


def test_block_stable_and_corner_no_wrap():
    g = parse_grid("##\n##")
    assert run(g, 5) == g
    g2 = parse_grid("#..\n...\n..#")
    assert count_alive(step(g2)) == 0


def test_bad_grid():
    for bad in ["..\n...\n", "..x\n", "#.\n\n#.\n"]:
        try:
            parse_grid(bad)
        except GridError:
            pass
        else:
            raise AssertionError(bad)


def test_empty_grid():
    g = parse_grid("")
    assert g == []
    assert render(run(g, 3)) == "alive: 0\n"
    assert parse_grid("\n\n") == []


def test_parse_generations():
    assert parse_generations(["3"]) == 3
    assert parse_generations(["0"]) == 0
    assert parse_generations([]) is None
    assert parse_generations(["-1"]) is None
    assert parse_generations(["abc"]) is None
    assert parse_generations(["1.5"]) is None


if __name__ == "__main__":
    sys.exit(main(sys.argv))
