# Spec: life

Conway's Game of Life on a finite grid.

Invocation: `life <generations>`; the starting grid is read from standard input.
- Input: lines of equal length made of `.` (dead) and `#` (alive). A trailing newline is optional;
  empty lines at the end are ignored. Cells outside the grid are always dead (no wrap-around).
- Rules per generation: a live cell with 2 or 3 live neighbours stays alive; a dead cell with exactly
  3 live neighbours becomes alive; every other cell is dead. Neighbours are the 8 surrounding cells.
- Output: the grid after the given number of generations, same format, then a final line
  `alive: <n>` with the number of live cells. Exit 0.
- Errors: missing or non-numeric generations, or a negative number: print exactly
  `usage: life <generations>` and exit 2. Lines of different lengths or other characters: print
  exactly `error: bad grid` and exit 1. Empty input is a valid 0x0 grid: print `alive: 0`.
- Grids up to 60x60 and 100 generations must finish within a few seconds.

Example: `life 1` with input
```
.....
..#..
..#..
..#..
.....
```
prints
```
.....
.....
.###.
.....
.....
alive: 3
```
The program must also contain at least three unit tests of its own pure logic.
A hidden acceptance test runs several grids and generation counts (including invalid input).
