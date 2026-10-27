# Test project 1 — Snake (terminal)

Success = an agent writes the game in GPLM only (no host-language code in this
folder) and every check below passes.

## Functional
1. `kaizo run apps/snake/main.gp` starts the game in the current terminal.
2. `kaizo build apps/snake/main.gp -o snake` produces a standalone executable
   that runs the same game without the source present.
3. Field is a bordered grid (default 20x15); snake starts with length 3, moving right.
4. Arrow keys and WASD change direction; reversing into itself is ignored.
5. Food appears on a random free cell; eating it grows the snake by 1 and adds 1 to score.
6. Hitting a wall or itself ends the game and prints "Game over. Score: N".
7. `q` quits at any time; the terminal is restored (echo, cursor) on every exit path.
8. Tick rate is fixed (default 150 ms) and does not depend on key presses.

## Verifiable without a human
- The game logic (step function: state + input -> new state) is pure and has
  GPLM tests: move, turn, reverse-ignored, eat+grow, wall death, self death.
- A seeded RNG makes food placement reproducible in tests.

## What this exercises in the core
Records/ADTs, pattern matching, lists, pure functions, tests; effects:
terminal raw mode, non-blocking key read, sleep/clock, random, stdout.
