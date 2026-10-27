#!/usr/bin/env bash
# Each tests/type_errors/*.gp is a wrong program; its "# expect:" line must appear in kaizo check.
cd "$(dirname "$0")/.."
K=${1:-build/kaizo}; fail=0
for f in tests/type_errors/*.gp; do
  want=$(sed -n 's/^# expect: //p' "$f")
  got=$($K check "$f" 2>&1)
  if [[ "$got" == *"$want"* ]]; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f"): wanted '$want', got: $got"; fail=1; fi
done
exit $fail
