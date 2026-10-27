# Minimal X11 client, speaking the X protocol directly over the server's Unix socket (no Xlib).
# Enough for simple 2D apps: one window, filled rectangles, text, key presses, expose, close.
# Drawing functions return request bytes; batch them and send once per frame with `send`.

type X = { sock: Conn, root: Int, id_base: Int, win: Int, gc: Int, font: Int, buf: String } end
type XEvent = XKey(String) | XExpose | XClosed | XOther end
type Polled = { x: X, events: List[XEvent] } end
type Auth = { name: String, data: String } end
type Rect = { x: Int, y: Int, w: Int, h: Int } end

# ---------- bytes ----------

fn lbytes(n: Int, k: Int) -> List[Int]
  list_map(list_range(0, k), fn(i) bit_and(bit_shr(n, mul(8, i)), 255) end)
end

fn bytes(s: String) -> List[Int]
  list_map(list_range(0, str_len(s)), fn(i) str_byte(s, i) end)
end

fn pad(n: Int) -> List[Int]
  list_map(list_range(0, mod(sub(4, mod(n, 4)), 4)), fn(i) 0 end)
end

fn cat_all(parts: List[List[Int]]) -> List[Int]
  list_fold(parts, [], fn(acc, p) list_concat(acc, p) end)
end

fn u16(s: String, off: Int) -> Int
  add(str_byte(s, off), mul(256, str_byte(s, add(off, 1))))
end

fn u32(s: String, off: Int) -> Int
  add(u16(s, off), mul(65536, u16(s, add(off, 2))))
end

fn be16(s: String, off: Int) -> Int
  add(mul(256, str_byte(s, off)), str_byte(s, add(off, 1)))
end

# a request: opcode, data byte, then the body; the length field is filled in (in 4-byte units)
fn request(opcode: Int, data: Int, body: List[Int]) -> String
  str_from_bytes(cat_all([[opcode, data], lbytes(add(1, div(list_len(body), 4)), 2), body]))
end

# ---------- authentication (~/.Xauthority, MIT-MAGIC-COOKIE-1) ----------

type AuthEntry = { num: String, name: String, data: String, next: Int } end

fn auth_entry(s: String, off: Int) -> AuthEntry
  let alen = be16(s, add(off, 2))
  let noff = add(add(off, 4), alen)
  let nlen = be16(s, noff)
  let moff = add(add(noff, 2), nlen)
  let mlen = be16(s, moff)
  let doff = add(add(moff, 2), mlen)
  let dlen = be16(s, doff)
  AuthEntry { num: str_slice(s, add(noff, 2), add(add(noff, 2), nlen)), name: str_slice(s, add(moff, 2), add(add(moff, 2), mlen)),
    data: str_slice(s, add(doff, 2), add(add(doff, 2), dlen)), next: add(add(doff, 2), dlen) }
end

fn find_auth(s: String, off: Int, display: String) -> Option[Auth]
  if ge(add(off, 4), str_len(s)) then None else
    let e = auth_entry(s, off)
    if and(eq(e.name, "MIT-MAGIC-COOKIE-1"), or(eq(e.num, display), eq(e.num, ""))) then Some(Auth { name: e.name, data: e.data })
    else find_auth(s, e.next, display) end
  end
end

fn read_auth(display: String) -> Auth ! [io, fs]
  let path = match env_get("XAUTHORITY")
    case Some(p) -> p
    case None -> str_cat(unwrap_or(env_get("HOME"), ""), "/.Xauthority")
  end
  match read_file(path)
    case Ok(s) -> unwrap_or(find_auth(s, 0, display), Auth { name: "", data: "" })
    case Err(_) -> Auth { name: "", data: "" }
  end
end

# ":0" / ":0.0" -> "0"
fn display_number(d: String) -> String
  let after = match str_find(d, ":")
    case Some(i) -> str_slice(d, add(i, 1), str_len(d))
    case None -> "0"
  end
  match str_find(after, ".")
    case Some(i) -> str_slice(after, 0, i)
    case None -> after
  end
end

# ---------- connection ----------

fn read_exact(c: Conn, n: Int, acc: String) -> Result[String, String] ! [net]
  if ge(str_len(acc), n) then Ok(acc) else
    match tcp_read(c, sub(n, str_len(acc)), 5000)
      case Ok(chunk) -> if eq(chunk, "") then Err("X server closed the connection") else read_exact(c, n, str_cat(acc, chunk)) end
      case Err(e) -> Err(e)
    end
  end
end

fn setup_request(a: Auth) -> String
  str_from_bytes(cat_all([[108, 0], lbytes(11, 2), lbytes(0, 2), lbytes(str_len(a.name), 2), lbytes(str_len(a.data), 2), [0, 0],
    bytes(a.name), pad(str_len(a.name)), bytes(a.data), pad(str_len(a.data))]))
end

# connects to $DISPLAY (default :0) and reads the server setup
fn open() -> Result[X, String] ! [io, fs, net]
  let num = display_number(unwrap_or(env_get("DISPLAY"), ":0"))
  match unix_connect(str_cat("/tmp/.X11-unix/X", num))
    case Err(e) -> Err(e)
    case Ok(c) ->
      tcp_write(c, setup_request(read_auth(num)))
      match read_exact(c, 8, "")
        case Err(e) -> Err(e)
        case Ok(head) ->
          match read_exact(c, add(8, mul(4, u16(head, 6))), head)
            case Err(e) -> Err(e)
            case Ok(s) ->
              if ne(str_byte(s, 0), 1) then Err(str_cat("X server refused the connection: ", str_slice(s, 8, add(8, str_byte(s, 1)))))
              else
                let vendor = u16(s, 24)
                let screen = add(add(40, add(vendor, mod(sub(4, mod(vendor, 4)), 4))), mul(8, str_byte(s, 29)))
                Ok(X { sock: c, root: u32(s, screen), id_base: u32(s, 12), win: 0, gc: 0, font: 0, buf: "" })
              end
          end
      end
  end
end

fn send(x: X, reqs: List[String]) -> Unit ! [net]
  tcp_write(x.sock, str_join(reqs, ""))
  Unit
end

# creates and shows a window with a drawing context and the "fixed" font
fn window(x: X, w: Int, h: Int, title: String) -> X ! [net]
  let win = add(x.id_base, 1)
  let gc = add(x.id_base, 2)
  let font = add(x.id_base, 3)
  # CreateWindow: background pixel (0x2) black, event mask (0x800): KeyPress | Exposure | StructureNotify
  let create = request(1, 0, cat_all([lbytes(win, 4), lbytes(x.root, 4), lbytes(0, 2), lbytes(0, 2), lbytes(w, 2), lbytes(h, 2), lbytes(0, 2), lbytes(1, 2), lbytes(0, 4),
    lbytes(0x802, 4), lbytes(0, 4), lbytes(0x28001, 4)]))
  # ChangeProperty WM_NAME (atom 39), type STRING (31), format 8
  let name = request(18, 0, cat_all([lbytes(win, 4), lbytes(39, 4), lbytes(31, 4), [8, 0, 0, 0], lbytes(str_len(title), 4), bytes(title), pad(str_len(title))]))
  # fixed size: WM_NORMAL_HINTS (40) of type WM_SIZE_HINTS (41), flags PMinSize | PMaxSize
  let hints = request(18, 0, cat_all([lbytes(win, 4), lbytes(40, 4), lbytes(41, 4), [32, 0, 0, 0], lbytes(18, 4), lbytes(48, 4), lbytes(0, 16), lbytes(w, 4), lbytes(h, 4), lbytes(w, 4), lbytes(h, 4), lbytes(0, 36)]))
  let open_font = request(45, 0, cat_all([lbytes(font, 4), lbytes(5, 2), [0, 0], bytes("fixed"), pad(5)]))
  # CreateGC: foreground (0x4), background (0x8), font (0x4000), graphics-exposures off (0x10000)
  let create_gc = request(55, 0, cat_all([lbytes(gc, 4), lbytes(win, 4), lbytes(0x1400C, 4), lbytes(0xFFFFFF, 4), lbytes(0, 4), lbytes(font, 4), lbytes(0, 4)]))
  let map_win = request(8, 0, lbytes(win, 4))
  send(x, [create, name, hints, open_font, create_gc, map_win])
  { x with win: win, gc: gc, font: font }
end

# ---------- drawing (each returns request bytes) ----------

fn color(x: X, rgb: Int) -> String
  request(56, 0, cat_all([lbytes(x.gc, 4), lbytes(4, 4), lbytes(rgb, 4)]))
end

fn fill(x: X, rgb: Int, rects: List[Rect]) -> String
  let body = list_fold(rects, [], fn(acc, r) list_concat(acc, cat_all([lbytes(r.x, 2), lbytes(r.y, 2), lbytes(r.w, 2), lbytes(r.h, 2)])) end)
  str_cat(color(x, rgb), request(70, 0, cat_all([lbytes(x.win, 4), lbytes(x.gc, 4), body])))
end

# text at (px, py) = left end of the baseline; drawn with a black background
fn text(x: X, rgb: Int, px: Int, py: Int, s: String) -> String
  let n = min(str_len(s), 255)
  str_cat(color(x, rgb), request(76, n, cat_all([lbytes(x.win, 4), lbytes(x.gc, 4), lbytes(px, 2), lbytes(py, 2), bytes(str_slice(s, 0, n)), pad(n)])))
end

# 24-bit colour as one 32-bit ZPixmap pixel (little-endian BGRX)
fn pixel(rgb: Int) -> String
  str_from_bytes([bit_and(rgb, 255), bit_and(bit_shr(rgb, 8), 255), bit_and(bit_shr(rgb, 16), 255), 0])
end

# an image of w x h pixels (rows of 4*w bytes) at (px, py); split into strips below the 256 KiB request limit
fn image(x: X, px: Int, py: Int, w: Int, h: Int, data: String) -> List[String]
  let per = max(1, div(240000, mul(w, 4)))
  list_map(list_range(0, div(add(h, sub(per, 1)), per)), fn(i)
    let y0 = mul(i, per)
    let rows = min(per, sub(h, y0))
    let part = str_slice(data, mul(mul(y0, w), 4), mul(mul(add(y0, rows), w), 4))
    request(72, 2, cat_all([lbytes(x.win, 4), lbytes(x.gc, 4), lbytes(w, 2), lbytes(rows, 2), lbytes(px, 2), lbytes(add(py, y0), 2), [0, 24, 0, 0], bytes(part)]))
  end)
end

# ---------- events ----------

# key names for the standard Linux (evdev) keycodes
fn key_name(code: Int) -> String
  match code
    case 9 -> "esc"
    case 24 -> "q"
    case 25 -> "w"
    case 27 -> "r"
    case 38 -> "a"
    case 39 -> "s"
    case 40 -> "d"
    case 65 -> "space"
    case 111 -> "up"
    case 113 -> "left"
    case 114 -> "right"
    case 116 -> "down"
    case _ -> ""
  end
end

fn parse_events(s: String, off: Int, acc: List[XEvent]) -> List[XEvent]
  if gt(add(off, 32), str_len(s)) then acc else
    let code = bit_and(str_byte(s, off), 127)
    let ev = if eq(code, 2) then XKey(key_name(str_byte(s, add(off, 1)))) elif eq(code, 12) then XExpose elif eq(code, 17) then XClosed else XOther end
    parse_events(s, add(off, 32), list_push(acc, ev))
  end
end

fn drain(x: X, acc: String) -> Polled ! [net]
  match tcp_read(x.sock, 4096, 0)
    case Ok(chunk) ->
      if eq(chunk, "") then Polled { x: x, events: [XClosed] } else drain(x, str_cat(acc, chunk)) end
    case Err(_) ->
      let all = str_cat(x.buf, acc)
      let whole = mul(div(str_len(all), 32), 32)
      Polled { x: { x with buf: str_slice(all, whole, str_len(all)) }, events: parse_events(all, 0, []) }
  end
end

# events that arrived since the last call (does not wait)
fn poll(x: X) -> Polled ! [net]
  drain(x, "")
end

fn close(x: X) -> Unit ! [net]
  tcp_close(x.sock)
end

# for tests: send a key press to a window (SendEvent of a KeyPress)
fn send_key(x: X, window: Int, keycode: Int) -> Unit ! [net]
  let ev = cat_all([[2, keycode], lbytes(0, 2), lbytes(0, 4), lbytes(x.root, 4), lbytes(window, 4), lbytes(0, 4), lbytes(0, 8), lbytes(0, 2), [1, 0]])
  send(x, [request(25, 0, cat_all([lbytes(window, 4), lbytes(1, 4), ev]))])
end

test "request length is in 4-byte units"
  expect_eq(str_len(request(8, 0, lbytes(5, 4))), 8)
  expect_eq(str_byte(request(8, 0, lbytes(5, 4)), 2), 2)
end

test "display number"
  expect_eq(display_number(":0"), "0")
  expect_eq(display_number("host:12.0"), "12")
end

test "xauthority entry"
  let entry = str_from_bytes(cat_all([[1, 0], [0, 2], bytes("pc"), [0, 1], bytes("0"), [0, 18], bytes("MIT-MAGIC-COOKIE-1"), [0, 3], [7, 8, 9]]))
  expect_eq(find_auth(entry, 0, "0"), Some(Auth { name: "MIT-MAGIC-COOKIE-1", data: str_from_bytes([7, 8, 9]) }))
  expect_eq(find_auth(entry, 0, "1"), None)
end

test "pixel is BGRX"
  expect_eq(bytes(pixel(0x112233)), [0x33, 0x22, 0x11, 0])
end

test "image strips stay below the request limit"
  let reqs = image(X { sock: Unit, root: 1, id_base: 0, win: 2, gc: 3, font: 4, buf: "" }, 0, 0, 640, 400, str_repeat(pixel(0), mul(640, 400)))
  expect_eq(list_len(reqs), 5)
  expect(lt(str_len(unwrap_or(list_get(reqs, 0), "")), 262140), "strip fits")
end

test "events"
  let key = str_from_bytes(list_concat([2, 111], lbytes(0, 30)))
  let expose = str_from_bytes(list_concat([12, 0], lbytes(0, 30)))
  expect_eq(parse_events(str_cat(key, expose), 0, []), [XKey("up"), XExpose])
end
