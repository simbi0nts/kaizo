# Test project 2 — "Hello world" page in a browser

Proposed interpretation (see step 0001): the GPLM app is the web *server*;
any existing browser is the client. Writing a browser is a separate, later
stretch project (2b), not a prerequisite.

## 2a — Hello web (main target)
1. `kaizo run apps/hello-web/main.gp` listens on `127.0.0.1:8080` (port via `--port`).
2. `GET /` returns `200`, `Content-Type: text/html; charset=utf-8`, a page
   whose `<h1>` is "Hello, world" (in a real browser it renders as a heading).
3. Any other path returns `404` with a short HTML body.
4. Handles sequential requests until Ctrl+C; one bad request does not kill the server.
5. `kaizo build ... -o hello-web` produces a standalone executable.
6. HTTP/1.1 parsing lives in `libs/http/` (GPLM), not in the core: the core only
   gives TCP sockets. This proves the "libraries" part of Theory 1.

Verifiable without a human: the request handler (request -> response) is pure
and tested in GPLM; an end-to-end test does `curl` against the running app.

## 2b — Mini text browser (stretch, later)
`kaizo run apps/mini-browser/main.gp http://127.0.0.1:8080/` fetches the page
over TCP, strips/interprets a tiny HTML subset (h1, p, a, br) and prints it to
the terminal. Reuses `libs/http/` from 2a — the second consumer of a library.
