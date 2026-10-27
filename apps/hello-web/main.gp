# Hello web — test project 2a. A GPLM web server; open it in any browser.
# Run: kaizo run apps/hello-web/main.gp [--port N]

import http

fn page() -> String
  str_join([
    "<!doctype html>",
    "<html lang=\"en\"><head><meta charset=\"utf-8\"><title>Hello from GPLM</title></head>",
    "<body><h1>Hello, world</h1><p>Served by an app written in GPLM (Project Kaizo).</p></body>",
    "</html>"], "\n")
end

fn not_found(path: String) -> String
  str_join(["<!doctype html><title>404</title><h1>404 Not Found</h1><p>No page at ", path, "</p>"], "")
end

# pure request -> response
fn handle(req: Request) -> Response
  if and(eq(req.method, "GET"), eq(req.path, "/")) then
    http.html(200, page())
  elif ne(req.method, "GET") then
    http.html(405, "<h1>405 Method Not Allowed</h1>")
  else
    http.html(404, not_found(req.path))
  end
end

fn port_arg(args: List[String]) -> Int
  match args
    case ["--port", p, .._] -> unwrap_or(str_to_int(p), 8080)
    case [_, ..rest] -> port_arg(rest)
    case [] -> 8080
  end
end

fn main() -> Unit ! [io, net]
  let addr = str_cat("127.0.0.1:", show(port_arg(args())))
  match http.serve(addr, handle)
    case Ok(_) -> Unit
    case Err(e) -> println(str_cat("cannot start server: ", e))
  end
end

fn get(path: String) -> Request
  Request { method: "GET", path: path, version: "HTTP/1.1", headers: [] }
end

test "GET / is the hello page"
  let r = handle(get("/"))
  expect_eq(r.status, 200)
  expect_eq(r.content_type, "text/html; charset=utf-8")
  expect(is_some(str_find(r.body, "<h1>Hello, world</h1>")), "page has the h1")
end

test "other paths are 404"
  let r = handle(get("/nope"))
  expect_eq(r.status, 404)
  expect(is_some(str_find(r.body, "/nope")), "404 names the path")
end

test "POST is 405"
  expect_eq(handle({ get("/") with method: "POST" }).status, 405)
end

test "port argument"
  expect_eq(port_arg([]), 8080)
  expect_eq(port_arg(["--port", "9000"]), 9000)
  expect_eq(port_arg(["-v", "--port", "9001"]), 9001)
  expect_eq(port_arg(["--port", "x"]), 8080)
end
