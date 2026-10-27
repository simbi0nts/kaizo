# Spec: inventory

A stock keeper driven by commands on standard input, one per line. Stock is kept per (location, item);
everything starts at 0. Names (locations and items) are one or more of `a-z`, `0-9`, `_`.
Quantities are positive whole numbers (digits only, no sign, not 0). Words are separated by single
spaces; there are no leading or trailing spaces in valid commands.

Commands (n = 1-based line number counting every line):
- `add <loc> <item> <qty>` — increase stock.
- `remove <loc> <item> <qty>` — decrease stock; if the stock there is smaller than qty, print
  `error: line <n>: not enough <item> at <loc>` and change nothing.
- `move <item> <qty> <from> <to>` — remove from `<from>` and add to `<to>` as one step; same error as
  remove if `<from>` has too little (then nothing changes). `<from>` equal to `<to>` is a bad command.
- `report` — print every (location, item) with non-zero stock, sorted by location, then item (byte
  order), one per line: `<loc> <item> <qty>`; if there is none, print `(empty)`.
- `total <item>` — print `<item> <sum over all locations>`.
- Empty lines and lines starting with `#` are ignored.
- Anything else (unknown command, wrong number of words, bad name or quantity): print
  `error: line <n>: bad command` and continue.

Errors are printed where they happen, between the other output. After the last line, exit 0 if there
was no error, otherwise exit 1.

Example input:
```
add main apple 5
add main pear 2
move apple 3 main shop
remove shop apple 4
total apple
report
```
output:
```
error: line 4: not enough apple at shop
apple 5
main apple 2
main pear 2
shop apple 3
```
exit code 1.
The program must also contain at least three unit tests of its own pure logic.
A hidden acceptance test feeds several command scripts (valid ones, every kind of error, 20,000 lines).
