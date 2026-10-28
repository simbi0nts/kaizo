# bench — GPLM vs C vs Rust (runtime performance)
`bench/run.sh [game_ticks] [render_frames] [server_seconds]` builds everything (gcc -O2,
rustc -C opt-level=3, kaizo build), checks that all versions print the same output, and prints a
markdown table (best of 3 wall times, max RSS, server req/s and p99, binary sizes).

| app | what it stresses | spec |
|---|---|---|
| game | game logic: small state updates, collision tests, RNG | game/SPEC.md |
| render3d | 3D animation: fixed-point transforms, sorting, scanline fill, per-pixel work | render3d/SPEC.md |
| server | high-load I/O: accept/read/write/close loop, 8 concurrent clients | server/SPEC.md |

All three use the same data structures: a grid/ring buffer (game) and a framebuffer (render3d); GPLM
updates its lists in place with `list_set` (step 0032). Kept for reference: `game/game_lists.gp`,
`render3d/render3d_spans.gp` (GPLM before in-place updates) and `game/game_list.c` (C with those
list-only structures). All are single-threaded.
Rust uses the standard library only.
