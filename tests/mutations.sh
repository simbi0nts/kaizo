#!/usr/bin/env bash
# Replays the mistakes that reached run time in the blind test (step 0006) on apps/todo-cli:
# each mutant must now be rejected by `kaizo check` (before running).
cd "$(dirname "$0")/.."
K=${1:-build/kaizo}; fail=0; tmp=$(mktemp -d)
mutate() { # name, sed expression
  mkdir -p "$tmp/$1"; sed "$2" apps/todo-cli/main.gp > "$tmp/$1/main.gp"
  if cmp -s apps/todo-cli/main.gp "$tmp/$1/main.gp"; then echo "FAIL $1: mutation did not apply"; fail=1; return; fi
  out=$($K check "$tmp/$1/main.gp" 2>&1)
  if [[ "$out" == *"error"* ]]; then echo "PASS $1 -> $(echo "$out" | head -1 | sed 's#.*/main.gp:##')"; else echo "FAIL $1: not caught"; fail=1; fi
}
mutate field_typo 's/t\.text))))/t.txt))))/'
mutate forgot_show 's/str_cat("added ", show(list_len(items)))/str_cat("added ", list_len(items))/'
mutate wrong_return '/^fn after(s: String, prefix: String) -> String/,/^end/s/^  str_trim(.*/  str_len(s)/'
rm -rf "$tmp"; exit $fail
