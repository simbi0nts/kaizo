# Step 0005 — Test project 2a: Hello web
Date: 2026-10-27
Status: done (criteria 1–6 of apps/hello-web/ACCEPTANCE.md pass; 2b mini browser not started)

## Goal
A GPLM app serves a Hello World page that renders in an ordinary browser,
with HTTP implemented in a GPLM library (core gives only TCP).

## What was done
- `libs/http/http.gp` — request parsing, headers, response rendering (byte-exact
  Content-Length), `serve` loop (sequential, 5 s read timeout, 64 KiB head limit,
  400 for malformed requests, logs one line per request). 3 tests. Pure parts are
  separated from the 3 effectful fns.
- `apps/hello-web/main.gp` — pure `handle(Request) -> Response` (200 / 404 / 405),
  `--port`. 4 tests.
- `tests/e2e.sh` — builds both apps as standalone executables and checks: 200 + content
  type + `<h1>Hello, world</h1>`, 404, raw garbage → 400, 20 sequential requests, then runs
  `tests/snake_pty.py`. Also checked by eye in a browser: renders as a heading.
- `make test` runs all GPLM suites (32 tests); `make e2e` runs tests/e2e.sh.

## Observations
- Again written without checker errors. Library sharing works (`import http`, `http.html`),
  types are global so the app uses `Request`/`Response` unqualified.
- Gap seen: the handler is passed as a value, so its effects are not tracked by v0
  (a handler that printed would not be rejected). Fix belongs to the type-checker step.

## How to verify
```
make test && make e2e
build/kaizo run apps/hello-web/main.gp --port 8080   # open http://127.0.0.1:8080/
```

## Next step
See STATUS.md → "Proposed next steps".
