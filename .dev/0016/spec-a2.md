# Spec: topword (step 0016 experiment, control arm a2 — reduced spec of arm c, in GPLM)

Write a GPLM program. It is run as `kaizo run topword.gp < input.txt`.

Behaviour:
- Read all of standard input (at most 4096 bytes; inputs are smaller).
- The input consists only of lowercase letters `a-z`, spaces and newlines. A word is a maximal
  run of letters.
- Print the most frequent word followed by a newline `\n` to standard output, and exit with code 0.
- Ties: if several words share the highest count, print the one whose **first occurrence** in the
  input comes earliest.
- Empty input (no words): print nothing, exit 0.
- Words are at most 32 letters; there are at most 200 distinct words.

Example: input `the cat and the dog and the bird\n` → output `the\n`.
Example: input `b a a b\n` → output `b\n` (tie; `b` occurs first).

The program must compute the answer from the input (a hidden test feeds several different inputs).

Deliverable: one GPLM source file. No unit tests are required.
