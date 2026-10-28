# bench — GPLM vs C vs Rust (runtime performance)
`bench/run.sh [game_ticks] [render_frames] [server_seconds]` builds everything (gcc -O2,
rustc -C opt-level=3, kaizo build), checks that all versions print the same output, and prints a
markdown table (best of 3 wall times, max RSS, server req/s and p99, binary sizes).

| app | what it stresses | spec |
|---|---|---|
| game | game logic: small state updates, collision tests, RNG | game/SPEC.md |
| render3d | 3D animation: fixed-point transforms, sorting, scanline fill, per-pixel work | render3d/SPEC.md |
| server | high-load I/O: accept/read/write/close loop, 8 concurrent clients | server/SPEC.md |

Each program is written the way its language makes natural: C and Rust use mutable arrays (grid,
framebuffer); GPLM has only immutable lists, so it uses lists (`game_list.c` is C with GPLM's data
structures, to separate code-generation cost from data-structure cost). All are single-threaded.
Rust uses the standard library only.
