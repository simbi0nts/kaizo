#!/bin/sh
# Hidden acceptance test for arm c. Usage: accept-c.sh <binary>
B=$1; pass=0; fail=0
t() { got=$(printf "$1" | timeout 5 "$B"; echo "ec=$?"); want=$(printf "$2"; echo "ec=0")
  if [ "$got" = "$want" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3: got [$got]"; fi; }
t 'the cat and the dog and the bird\n' 'the\n' example
t 'b a a b\n' 'b\n' tie-first
t '' '' empty
t '   \n\n' '' blanks
t 'zebra' 'zebra\n' single-no-newline
t 'x yy x yy yy\nzz zz zz zz\n' 'zz\n' multiline
t 'abcdefghijklmnopqrstuvwxyzabcdef q abcdefghijklmnopqrstuvwxyzabcdef\n' 'abcdefghijklmnopqrstuvwxyzabcdef\n' long-word
t 'ab abc ab abc abc a\n' 'abc\n' prefixes
echo "accept-c: $pass passed, $fail failed"; [ $fail = 0 ]
