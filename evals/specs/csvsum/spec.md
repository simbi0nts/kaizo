# Spec: csvsum

Group and sum a CSV file read from standard input.

Invocation: `csvsum <group-column> <sum-column>` (column names from the header). Wrong number of
arguments: print exactly `usage: csvsum <group-column> <sum-column>` and exit 2.

CSV format (input uses `\n` line endings only):
- A record is a list of fields separated by `,`, ending at a newline (the last record may lack it).
- A field is either unquoted (any characters except `,`, `"` and newline) or quoted: starts with `"`,
  ends with the next `"` that is not doubled; inside, `""` stands for one `"`, and commas and newlines
  are part of the field. After the closing quote the next character must be `,`, a newline or the end.
- The first record is the header (column names). Records are numbered from 1 (the header is record 1).

Behaviour:
- No input at all: print `error: no header`, exit 1. A column name not in the header: print
  `error: no column <name>` (the first missing one, group column checked first), exit 1.
- Every other record must have as many fields as the header, its sum-column value must be an integer
  (optional leading `-`, then digits; nothing else), and its quoting must be valid; otherwise print
  `error: record <n>` for the first bad record and exit 1. A quote that is never closed makes the
  record it starts in bad.
- Output: for each distinct value of the group column, sorted by byte order, a line `<group>,<sum>`.
  Write the group value quoted (with inner `"` doubled) if it contains `,`, `"` or a newline,
  otherwise as is. Exit 0. A header with no data records prints nothing.

Example input for `csvsum city amount`:
```
city,amount,note
Oslo,10,first
"Rome, IT",5,"says ""hi"""
Oslo,-3,
```
output:
```
Oslo,7
"Rome, IT",5
```
The program must also contain at least three unit tests of its own pure logic.
A hidden acceptance test feeds several CSV inputs, including quoted fields with commas, quotes and
newlines, malformed records and a large file (20,000 records).
