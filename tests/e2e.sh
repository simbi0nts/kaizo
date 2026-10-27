#!/usr/bin/env bash
# End-to-end checks of both test projects against built standalone executables.
set -u
cd "$(dirname "$0")/.."
K=build/kaizo
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }

$K build apps/hello-web/main.gp -o build/hello-web >/dev/null || bad "build hello-web"
$K build apps/snake/main.gp -o build/snake >/dev/null || bad "build snake"

PORT=18080
build/hello-web --port $PORT > build/hello-web.log 2>&1 &
PID=$!
for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.1; done

r=$(curl -s -i "http://127.0.0.1:$PORT/")
[[ "$r" == "HTTP/1.1 200 OK"* ]] && ok "GET / is 200" || bad "GET / is 200: $r"
[[ "$r" == *"Content-Type: text/html; charset=utf-8"* ]] && ok "content type" || bad "content type"
[[ "$r" == *"<h1>Hello, world</h1>"* ]] && ok "hello h1" || bad "hello h1"
[[ $(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/missing") == 404 ]] && ok "404 path" || bad "404 path"
printf 'garbage\r\n\r\n' | timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$PORT; cat >&3; head -c 12 <&3" | grep -q "400" && ok "bad request is 400" || bad "bad request is 400"
for i in $(seq 20); do curl -s -o /dev/null "http://127.0.0.1:$PORT/"; done
[[ $(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/") == 200 ]] && ok "survives many requests" || bad "survives many requests"
kill $PID; wait $PID 2>/dev/null

python3 tests/snake_pty.py build/snake || fail=1
exit $fail
