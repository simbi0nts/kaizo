# Step 0014 — Snake with a GUI (X11, protocol written in GPLM)
Date: 2026-10-27
Status: done (Linux/X11). Windows (GDI) and macOS (Cocoa) GUIs not started.

## Goal
Human: "Let's try to build snake game with GUI."

## Decisions
- Same pattern as hello-web: the core gets one tiny primitive, everything else is GPLM.
  New builtin `unix_connect(path)` (effect `net`; Linux + macOS; Windows reports unsupported).
- `libs/x11` (~240 lines): the X11 wire protocol itself — no Xlib, no C. Xauthority parsing
  (MIT-MAGIC-COOKIE-1), connection setup, CreateWindow, WM_NAME, fixed-size hints, OpenFont,
  CreateGC/ChangeGC, PolyFillRectangle, ImageText8, non-blocking event polling (key press, expose,
  close), SendEvent (for tests). Keycodes assume the standard Linux evdev map.
- Game logic moved from apps/snake to `libs/snake` (12 tests); both the terminal and the GUI app
  import it — second real case of library sharing.
- `apps/snake-gui` (~110 lines): 20x15 board, 24 px cells, score bar; arrows/WASD, r restart, q/Esc quit.
  Each frame is one batched write of X requests.

## Verification
- `make test`: 10 suites incl. libs/x11 (4), libs/snake (12), apps/snake-gui (2).
- `make gui` (tests/gui_snake.sh, needs a display): window opens at 480x396, keys sent with
  `tests/x11_sendkey.gp` (also GPLM) steer the snake, q closes it, final score printed.
- Screenshots taken with `import`: start, after `r up`, after `right` — see `img/0014-snake-gui.png`.
- Terminal Snake e2e, hello-web e2e, fixpoint: unchanged and passing.

## Observations
- Named my byte helper `le` again → the checker rejected it (builtin `le` = less-or-equal) — same
  slip as in step 0009; LLM habit, caught instantly.
- One more hand-computed bit mask was wrong (0x1C00C vs 0x1400C) — caught by review this time;
  hex literals (0012) at least made it readable.

## Next
GUI on Windows via user32/gdi32 (prim_ccall makes this a library, no core change), then macOS.
