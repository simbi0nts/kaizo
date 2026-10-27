#!/usr/bin/env bash
# Hidden acceptance test of one spec. usage: evals/score.sh <spec> <command...>
# Each evals/specs/<spec>/cases/<name>.args holds the arguments (one per line; "{spec}" = the spec
# directory) and an optional <name>.stdin. The candidate's stdout+stderr and exit code must equal
# those of reference.py. Prints PASS/FAIL per case and a final JSON line.
set -u
spec=$1; shift
D=$(cd "$(dirname "$0")/specs/$spec" && pwd)
pass=0; total=0
for a in "$D"/cases/*.args; do
  name=$(basename "$a" .args); total=$((total+1))
  mapfile -t args < "$a"
  args=("${args[@]//\{spec\}/$D}")
  in="$D/cases/$name.stdin"; [ -f "$in" ] || in=/dev/null
  exp=$(python3 "$D/reference.py" "${args[@]}" < "$in" 2>&1); eec=$?
  got=$(timeout 20 "$@" "${args[@]}" < "$in" 2>&1); gec=$?
  if [ "$exp" == "$got" ] && [ $eec == $gec ]; then pass=$((pass+1)); echo "PASS $name"
  else echo "FAIL $name (exit: want $eec, got $gec)"; diff <(echo "$exp") <(echo "$got") | head -8; fi
done
echo "{\"spec\": \"$spec\", \"passed\": $pass, \"total\": $total}"
[ $pass == $total ]
