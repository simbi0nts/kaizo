# Minimal HTTP/1.1 server library. The core only provides TCP; all HTTP is here, in GPLM.
# Usage: http.serve("127.0.0.1:8080", handler)  where handler: Fn(Request) -> Response

type Header = { name: String, value: String } end
type Request = { method: String, path: String, version: String, headers: List[Header] } end
type Response = { status: Int, content_type: String, body: String } end

let max_head = 65536

# ---------- pure ----------

fn parse_header(line: String) -> Option[Header]
  match str_find(line, ":")
    case Some(i) -> Some(Header { name: str_lower(str_trim(str_slice(line, 0, i))), value: str_trim(str_slice(line, add(i, 1), str_len(line))) })
    case None -> None
  end
end

fn parse_headers(lines: List[String]) -> List[Header]
  list_fold(lines, [], fn(acc, line)
    match parse_header(line)
      case Some(h) -> list_push(acc, h)
      case None -> acc
    end
  end)
end

fn parse_request(raw: String) -> Result[Request, String]
  match str_find(raw, "\r\n\r\n")
    case None -> Err("incomplete request head")
    case Some(i) ->
      match str_split(str_slice(raw, 0, i), "\r\n")
        case [first, ..rest] ->
          match str_split(first, " ")
            case [m, p, v] ->
              if and(str_starts(v, "HTTP/1."), str_starts(p, "/")) then
                Ok(Request { method: m, path: p, version: v, headers: parse_headers(rest) })
              else
                Err("bad request line")
              end
            case _ -> Err("bad request line")
          end
        case [] -> Err("empty request")
      end
  end
end

fn header(req: Request, name: String) -> Option[String]
  match list_filter(req.headers, fn(h) eq(h.name, str_lower(name)) end)
    case [h, .._] -> Some(h.value)
    case [] -> None
  end
end

fn status_text(code: Int) -> String
  match code
    case 200 -> "OK"
    case 400 -> "Bad Request"
    case 404 -> "Not Found"
    case 405 -> "Method Not Allowed"
    case 500 -> "Internal Server Error"
    case _ -> "Unknown"
  end
end

fn html(status: Int, body: String) -> Response
  Response { status: status, content_type: "text/html; charset=utf-8", body: body }
end

fn render_response(r: Response) -> String
  str_join([
    "HTTP/1.1 ", show(r.status), " ", status_text(r.status), "\r\n",
    "Content-Type: ", r.content_type, "\r\n",
    "Content-Length: ", show(str_len(r.body)), "\r\n",
    "Connection: close\r\n",
    "\r\n",
    r.body], "")
end

# ---------- effects ----------

fn read_head(c: Conn, acc: String) -> String ! [net]
  if or(is_some(str_find(acc, "\r\n\r\n")), gt(str_len(acc), max_head)) then
    acc
  else
    match tcp_read(c, 4096, 5000)
      case Ok(chunk) -> if eq(chunk, "") then acc else read_head(c, str_cat(acc, chunk)) end
      case Err(_) -> acc
    end
  end
end

fn handle_conn(c: Conn, handler: Fn(Request) -> Response) -> Unit ! [net, io]
  let parsed = parse_request(read_head(c, ""))
  let resp = match parsed
    case Ok(req) -> handler(req)
    case Err(e) -> html(400, str_join(["<h1>400 Bad Request</h1><p>", e, "</p>"], ""))
  end
  tcp_write(c, render_response(resp))
  tcp_close(c)
  let line = match parsed
    case Ok(req) -> str_join([req.method, " ", req.path], "")
    case Err(e) -> str_cat("bad request: ", e)
  end
  println(str_join([show(resp.status), " ", line], ""))
end

fn accept_loop(l: Listener, handler: Fn(Request) -> Response) -> Unit ! [net, io]
  match tcp_accept(l)
    case Ok(c) ->
      handle_conn(c, handler)
      accept_loop(l, handler)
    case Err(e) ->
      println(str_cat("accept failed: ", e))
      accept_loop(l, handler)
  end
end

# serves requests one by one until the process is stopped; Err only if it cannot listen
fn serve(addr: String, handler: Fn(Request) -> Response) -> Result[Unit, String] ! [net, io]
  match tcp_listen(addr)
    case Err(e) -> Err(e)
    case Ok(l) ->
      println(str_cat("listening on http://", addr))
      accept_loop(l, handler)
      Ok(Unit)
  end
end

# ---------- tests ----------

test "parse a GET request"
  let r = parse_request("GET /a?b=1 HTTP/1.1\r\nHost: x\r\nUser-Agent: t\r\n\r\n")
  match r
    case Ok(req) ->
      expect_eq(req.method, "GET")
      expect_eq(req.path, "/a?b=1")
      expect_eq(header(req, "HOST"), Some("x"))
      expect_eq(header(req, "accept"), None)
    case Err(e) -> panic(e)
  end
end

test "reject bad requests"
  expect_eq(parse_request("GET / HTTP/1.1\r\n"), Err("incomplete request head"))
  expect_eq(parse_request("garbage\r\n\r\n"), Err("bad request line"))
  expect_eq(parse_request("GET / SPDY/9\r\n\r\n"), Err("bad request line"))
end

test "render a response with byte length"
  expect_eq(render_response(html(200, "hé")), "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: 3\r\nConnection: close\r\n\r\nhé")
end
