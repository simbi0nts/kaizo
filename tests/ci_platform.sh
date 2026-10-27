#!/usr/bin/env bash
# Runs the platform checks with a native kaizo binary on its own OS.
# usage: tests/ci_platform.sh <kaizo-binary> <target> <dist-dir>
# The dist dir holds the binaries cross-built on Linux (kaizo-<target>[.exe]) for the fixpoint check.
set -u
K=$1; T=$2; DIST=$3
EXE=""; [[ $T == windows-* ]] && EXE=".exe"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }
mkdir -p out

"$K" version && ok "kaizo runs ($T)" || bad "kaizo runs"

for s in tests/selftest.gp libs/rand libs/http libs/map libs/sha256 libs/snake libs/x11 apps/snake/main.gp apps/snake-gui/main.gp apps/demo3d/main.gp apps/hello-web/main.gp apps/todo-cli/main.gp apps/wordfreq/main.gp; do
  "$K" test "$s" > out/test.log 2>&1 && ok "suite $s" || { bad "suite $s"; cat out/test.log; }
done

# the core must rebuild itself on this OS byte-for-byte equal to the Linux cross build, for every target
for t in linux-x64 windows-x64 macos-x64 macos-arm64; do
  e=""; [[ $t == windows-* ]] && e=".exe"
  "$K" build core -o "out/kaizo-$t$e" --target "$t" > /dev/null && cmp "out/kaizo-$t$e" "$DIST/kaizo-$t$e" \
    && ok "fixpoint: kaizo on $T builds identical kaizo for $t" || bad "fixpoint for $t"
done

# hello web over real HTTP
"$K" build apps/hello-web/main.gp -o "out/hello-web$EXE" > /dev/null || bad "build hello-web"
"out/hello-web$EXE" --port 18080 > out/web.log 2>&1 &
PID=$!
for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:18080/" && break; sleep 0.2; done
r=$(curl -s -i "http://127.0.0.1:18080/")
[[ "$r" == "HTTP/1.1 200 OK"* && "$r" == *"<h1>Hello, world</h1>"* ]] && ok "hello-web 200 + h1" || bad "hello-web 200: $r"
[[ $(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:18080/nope") == 404 ]] && ok "hello-web 404" || bad "hello-web 404"
kill $PID 2>/dev/null; wait $PID 2>/dev/null

# snake: full terminal test where a pty exists, otherwise the non-terminal message
"$K" build apps/snake/main.gp -o "out/snake$EXE" > /dev/null || bad "build snake"
if [[ $T == windows-* ]]; then
  echo "" | "out/snake$EXE" | grep -q "interactive terminal" && ok "snake without console reports it" || bad "snake without console"
else
  python3 tests/snake_pty.py "out/snake" || fail=1
fi
exit $fail
