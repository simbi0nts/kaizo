# Spec: ledger

Account balances from a list of transfers.

Invocation: no arguments; transfers are read from standard input, one per line:
`<from>,<to>,<amount>` where from/to are account names (letters, digits, `_`; non-empty) and amount
is a positive whole number of cents (digits only). Empty lines are ignored.
- Every account starts at 0. A transfer subtracts the amount from `from` and adds it to `to`.
- Output: one line per account that appears in the input, sorted by name (byte order):
  `<name> <balance>` where balance is in cents and may be negative (`-150`). Exit 0.
- If any line is malformed (wrong number of fields, bad name, amount missing/zero/not digits,
  from equal to to): print nothing else but `error: line <n>` (1-based line number counting
  every input line, including empty ones) for the first bad line, and exit 1.
- Up to 10,000 lines must finish within a few seconds.

Example input
```
alice,bob,500
bob,carol,200

carol,alice,50
```
output
```
alice -450
bob 300
carol 150
```
The program must also contain at least three unit tests of its own pure logic.
A hidden acceptance test feeds several inputs, including malformed ones and a large one.
