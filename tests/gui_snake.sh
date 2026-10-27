#!/usr/bin/env bash
# GUI Snake end-to-end on a real X display: window appears, keys steer, q closes. Needs DISPLAY, xwininfo.
set -u
cd "$(dirname "$0")/.."
K=build/kaizo; fail=0
ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=1; }
$K build apps/snake-gui/main.gp -o build/snake-gui >/dev/null && $K build tests/x11_sendkey.gp -o build/sendkey >/dev/null || bad "build"
build/snake-gui > build/snake-gui.log 2>&1 &
PID=$!
for _ in $(seq 30); do xwininfo -name "Kaizo Snake" >/dev/null 2>&1 && break; sleep 0.1; done
W=$(xwininfo -name "Kaizo Snake" 2>/dev/null | awk '/Window id/{print $4}')
[[ -n "$W" ]] && ok "window opened" || bad "window opened"
size=$(xwininfo -id "$W" 2>/dev/null | awk '/Width|Height/{printf "%s ", $2}')
[[ "$size" == "480 396 " ]] && ok "window is 480x396" || bad "window size: $size"
build/sendkey "$W" 27 111 114 && ok "keys sent" || bad "keys sent"
build/sendkey "$W" 24; sleep 0.5
kill -0 $PID 2>/dev/null && { bad "q closes the game"; kill $PID; } || ok "q closes the game"
grep -q "Game over. Score:" build/snake-gui.log && ok "prints final score" || bad "prints final score"
exit $fail
