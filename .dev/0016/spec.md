# Spec: wordfreq (step 0016 experiment, arms a and b)

A command-line program that prints the 10 most frequent words of a text file.

Invocation: the program receives one argument, a file path. (`args()` returns the
arguments without the program name, so the path is the first element.)

Behaviour:
1. No argument: print exactly `usage: wordfreq <file>` (one line) and exit with code 2.
2. The file cannot be read: print exactly `error: cannot read <path>` (with the given path)
   and exit with code 1.
3. Otherwise:
   - A **word** is a maximal run of ASCII letters `A-Z` / `a-z`. Every other byte
     (digits, punctuation, apostrophes, hyphens, whitespace, non-ASCII bytes) separates words.
     So `don't` is the two words `don` and `t`.
   - Words are compared case-insensitively and printed in lower case.
   - Count every word. Sort by count, highest first; equal counts are ordered by the word in
     ascending byte order (`a` before `b`).
   - Print the first 10 entries (fewer if there are fewer distinct words), one per line, as
     `<count> <word>`, e.g. `4 the`. Nothing else is printed. Exit code 0.
   - An empty file or a file without words prints nothing and exits 0.
4. Files up to ~50 KB must finish within a few seconds.

Example: for the file
```
The cat and the hat. The cat sat!
A hat, a cat; THE END.
```
the output is
```
4 the
3 cat
2 a
2 hat
1 and
1 end
1 sat
```

The program must also contain at least three unit tests of its own pure logic
(word splitting, counting, ordering).

A hidden acceptance test (not shown to you) runs the program on several files, including the
example above, an empty file, a file without letters, a file with many ties, a ~40 KB file,
a missing file and no argument, and compares stdout and the exit code exactly.
