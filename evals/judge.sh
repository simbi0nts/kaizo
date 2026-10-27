#!/usr/bin/env bash
# Step 2 of the protocol for one candidate. usage: evals/judge.sh <gplm|python> <spec> <file>
# Prints "STAGE <name>" lines, then either "VERDICT ok" or "VERDICT feedback" followed by the text
# that is sent back to the agent (a fix round).
set -u
arm=$1; spec=$2; f=$3; K=${KAIZO:-build/kaizo}; dir=$(mktemp -d)
feedback() { echo "VERDICT feedback"; echo "$1"; rm -rf "$dir"; exit 1; }
if [ "$arm" = gplm ]; then
  cp "$f" "$dir/main.gp"
  out=$($K check "$dir/main.gp" 2>&1) || feedback "kaizo check:
${out//$dir\//}"
  echo "STAGE check ok"
  out=$($K test "$dir/main.gp" 2>&1) || feedback "kaizo test:
${out//$dir\//}"
  echo "STAGE own-tests ok ($(echo "$out" | tail -1))"
  $K build "$dir/main.gp" -o "$dir/prog" >/dev/null 2>&1 || feedback "kaizo build failed"
  cmd=("$dir/prog")
else
  cp "$f" "$dir/prog.py"
  out=$(python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$dir/prog.py" 2>&1) || feedback "python syntax:
$out"
  echo "STAGE syntax ok"
  out=$(cd "$dir" && python3 "$OLDPWD/evals/run_py_tests.py" prog.py 2>&1) || feedback "own tests:
$out"
  echo "STAGE own-tests ok ($(echo "$out" | tail -1))"
  cmd=(python3 "$dir/prog.py")
fi
res=$(evals/score.sh "$spec" "${cmd[@]}" 2>&1)
echo "STAGE hidden $(echo "$res" | tail -1)"
if echo "$res" | grep -q "^FAIL"; then
  first=$(echo "$res" | awk '/^FAIL/{p=1} p' | head -10)
  feedback "hidden acceptance test, first failing case:
$first"
fi
echo "VERDICT ok"; rm -rf "$dir"
