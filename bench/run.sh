#!/usr/bin/env bash
# Benchmarks GPLM vs C (gcc -O2) vs Rust (rustc -C opt-level=3) on three apps; prints a markdown table.
# usage: bench/run.sh [game_ticks] [render_frames] [server_seconds]
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
GT=${1:-2000000}; RF=${2:-2000}; SS=${3:-5}
K=${KAIZO:-build/kaizo}; RUSTC=${RUSTC:-$(command -v rustc || echo ~/.cargo/bin/rustc)}
B=build/bench; mkdir -p $B
for app in game render3d; do
  gcc -O2 -o $B/${app}_c bench/$app/$app.c
  "$RUSTC" -C opt-level=3 -o $B/${app}_rs bench/$app/$app.rs
  $K build bench/$app/$app.gp -o $B/${app}_gp > /dev/null
done
gcc -O2 -o $B/server_c bench/server/server.c 2>/dev/null
"$RUSTC" -C opt-level=3 -o $B/server_rs bench/server/server.rs
$K build bench/server/server.gp -o $B/server_gp > /dev/null
gcc -O2 -pthread -o $B/load bench/server/load.c

best() { # best wall time of 3 runs (s), max RSS of the last run (KB), output (checked equal)
  local b=9999 out rss t0 t1 d
  for i in 1 2 3; do
    t0=$(date +%s.%N); out=$(/usr/bin/time -f "%M" -o $B/rss "$@"); t1=$(date +%s.%N)
    d=$(echo "$t1 - $t0" | bc); b=$(echo "if ($d < $b) $d else $b" | bc)
  done
  printf "%.3f %s %s\n" "$b" "$(cat $B/rss)" "${out// /_}"
}
echo "| app | metric | C | Rust | GPLM | GPLM/C | GPLM/Rust |"
echo "|---|---|---:|---:|---:|---:|---:|"
for app in game render3d; do
  arg=$GT; [ $app = render3d ] && arg=$RF
  read tc mc oc < <(best $B/${app}_c $arg); read tr mr or_ < <(best $B/${app}_rs $arg); read tg mg og < <(best $B/${app}_gp $arg)
  [ "$oc" = "$or_" ] && [ "$oc" = "$og" ] || echo "OUTPUT MISMATCH $app: $oc / $or_ / $og"
  awk -v a=$app -v n=$arg -v c=$tc -v r=$tr -v g=$tg 'BEGIN{printf "| %s (%s) | time s | %.3f | %.3f | %.3f | %.1fx | %.1fx |\n", a, n, c, r, g, g/c, g/r}'
  echo "| $app | max RSS KB | $mc | $mr | $mg | | |"
done
port=18300
for lang in c rs gp; do
  port=$((port + 1)); $B/server_$lang $port > /dev/null 2>&1 & pid=$!; sleep 0.5
  res[$((port % 10))]="$($B/load $port 8 $SS)"; kill $pid; wait $pid 2>/dev/null || true
done
rc=$(echo ${res[1]} | awk '{print $2}'); rr=$(echo ${res[2]} | awk '{print $2}'); rg=$(echo ${res[3]} | awk '{print $2}')
pc=$(echo ${res[1]} | awk '{print $6}'); pr=$(echo ${res[2]} | awk '{print $6}'); pg=$(echo ${res[3]} | awk '{print $6}')
awk -v c=$rc -v r=$rr -v g=$rg 'BEGIN{printf "| server (8 clients) | req/s | %d | %d | %d | %.2fx | %.2fx |\n", c, r, g, g/c, g/r}'
echo "| server | p99 ms | $pc | $pr | $pg | | |"
echo "| binary size KB | game / render3d / server | $(( $(stat -c %s $B/game_c)/1024 )) / $(( $(stat -c %s $B/render3d_c)/1024 )) / $(( $(stat -c %s $B/server_c)/1024 )) | $(( $(stat -c %s $B/game_rs)/1024 )) / $(( $(stat -c %s $B/render3d_rs)/1024 )) / $(( $(stat -c %s $B/server_rs)/1024 )) | $(( $(stat -c %s $B/game_gp)/1024 )) / $(( $(stat -c %s $B/render3d_gp)/1024 )) / $(( $(stat -c %s $B/server_gp)/1024 )) | | |"
