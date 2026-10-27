# Spec: roman

A command-line converter between decimal numbers and Roman numerals.

Invocation: one argument.
1. No argument or more than one: print exactly `usage: roman <number|numeral>` and exit with code 2.
2. A decimal number 1..3999 (digits only, no sign, no leading `+`): print its Roman numeral in
   canonical form (I V X L C D M with subtractive pairs IV IX XL XC CD CM), exit 0.
   Example: `1994` -> `MCMXCIV`, `4` -> `IV`, `3999` -> `MMMCMXCIX`.
3. A Roman numeral (letters IVXLCDM, upper or lower case): print its decimal value, exit 0 —
   but only if it is in canonical form (the numeral the program would print for that value,
   ignoring case). Example: `mcmxciv` -> `1994`.
4. Anything else (0, 4000, negative numbers, `IIII`, `VX`, `abc`, an empty string): print exactly
   `error: invalid input <arg>` with the given argument and exit with code 1.

The program must also contain at least three unit tests of its own pure logic.
A hidden acceptance test runs the program with many valid and invalid arguments and compares the
output and the exit code exactly.
