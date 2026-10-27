#!/bin/sh
# Hidden acceptance test for the wordfreq spec. Usage: accept.sh <command...>
# e.g. accept.sh build/kaizo run apps/wordfreq/main.gp
# Compares stdout and exit code against reference.py for every fixture.
D=$(cd "$(dirname "$0")" && pwd)
pass=0; fail=0
run_case() {
  name=$1; shift
  exp=$(python3 "$D/reference.py" "$@"); eec=$?
  got=$(timeout 20 $CMD "$@" 2>&1); gec=$?
  if [ "$exp" = "$got" ] && [ $eec = $gec ]; then pass=$((pass+1)); echo "PASS $name"
  else fail=$((fail+1)); echo "FAIL $name (exit want $eec got $gec)"; echo "--- want"; echo "$exp"; echo "--- got"; echo "$got" | head -20; fi
}
CMD="$*"
for f in small empty nowords ties big; do run_case "$f" "$D/fixtures/$f.txt"; done
run_case missing-file /nonexistent/file.txt
# no-argument case
exp="usage: wordfreq <file>"; got=$(timeout 20 $CMD 2>&1); gec=$?
if [ "$exp" = "$got" ] && [ $gec = 2 ]; then pass=$((pass+1)); echo "PASS no-args"; else fail=$((fail+1)); echo "FAIL no-args (exit $gec): $got"; fi
echo "accept: $pass passed, $fail failed"
[ $fail = 0 ]
