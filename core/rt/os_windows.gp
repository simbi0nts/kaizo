# OS layer: Windows x64, via kernel32.dll and ws2_32.dll (no C runtime).
# prim_ccall returns the raw 64-bit result; prim_ccall32 sign-extends a 32-bit (BOOL/int) result.

let h_in = prim_ccall("GetStdHandle", [-10])
let h_out = prim_ccall("GetStdHandle", [-11])
let h_err = prim_ccall("GetStdHandle", [-12])
let wsa_ok = prim_ccall32("ws2_32.dll!WSAStartup", [0x202, prim_addr(zeros(512))])

fn last_error() -> Int
  prim_ccall32("GetLastError", [])
end

fn win_errmsg(code: Int) -> String
  match code
    case 2 -> "no such file or directory"
    case 3 -> "path not found"
    case 5 -> "access denied"
    case 32 -> "file is in use"
    case 10013 -> "permission denied"
    case 10048 -> "address already in use"
    case 10049 -> "cannot assign requested address"
    case 10054 -> "connection reset by peer"
    case 10060 -> "i/o timeout"
    case e -> str_cat("windows error ", show(e))
  end
end

fn os_errmsg(r: Int) -> String
  win_errmsg(sub(0, r))
end

fn write_handle(h: Int, s: String, off: Int) -> Int
  let n = prim_len(s)
  if ge(off, n) then 0 else
    let done = zeros(8)
    let ok = prim_ccall32("WriteFile", [h, add(prim_addr(s), off), sub(n, off), prim_addr(done), 0])
    if eq(ok, 0) then sub(0, last_error()) else write_handle(h, s, add(off, u_le(done, 0, 4))) end
  end
end

fn os_write(fd: Int, s: String) -> Int
  write_handle(if eq(fd, 2) then h_err else h_out end, s, 0)
end

fn os_read_byte() -> Int
  let buf = zeros(1)
  let got = zeros(8)
  let ok = prim_ccall32("ReadFile", [h_in, prim_addr(buf), 1, prim_addr(got), 0])
  if or(eq(ok, 0), eq(u_le(got, 0, 4), 0)) then -1 else prim_byte(buf, 0) end
end

# ---------- command line (MSVC argument rules) ----------

type ArgSt = { args: List[String], cur: List[Int], in_arg: Bool, quoted: Bool, slashes: Int } end

fn flush_slashes(st: ArgSt, n: Int) -> List[Int]
  if le(n, 0) then st.cur else flush_slashes({ st with cur: list_push(st.cur, 92) }, sub(n, 1)) end
end

fn parse_cmdline(s: String, i: Int, st: ArgSt) -> List[String]
  if ge(i, prim_len(s)) then
    let cur = flush_slashes(st, st.slashes)
    if st.in_arg then list_push(st.args, str_from_bytes(cur)) else st.args end
  else
    let c = prim_byte(s, i)
    if eq(c, 92) then parse_cmdline(s, add(i, 1), { st with slashes: add(st.slashes, 1), in_arg: true })
    elif eq(c, 34) then
      let cur = flush_slashes({ st with cur: st.cur }, div(st.slashes, 2))
      if eq(mod(st.slashes, 2), 1) then parse_cmdline(s, add(i, 1), { st with cur: list_push(cur, 34), slashes: 0, in_arg: true })
      else parse_cmdline(s, add(i, 1), { st with cur: cur, slashes: 0, quoted: not(st.quoted), in_arg: true }) end
    elif and(or(eq(c, 32), eq(c, 9)), not(st.quoted)) then
      let cur = flush_slashes(st, st.slashes)
      let args2 = if st.in_arg then list_push(st.args, str_from_bytes(cur)) else st.args end
      parse_cmdline(s, add(i, 1), ArgSt { args: args2, cur: [], in_arg: false, quoted: false, slashes: 0 })
    else
      parse_cmdline(s, add(i, 1), { st with cur: list_push(flush_slashes(st, st.slashes), c), slashes: 0, in_arg: true })
    end
  end
end

fn os_args() -> List[String]
  let all = parse_cmdline(cstring_at(prim_ccall("GetCommandLineA", [])), 0, ArgSt { args: [], cur: [], in_arg: false, quoted: false, slashes: 0 })
  list_slice(all, 1, list_len(all))
end

fn quote_arg(a: String) -> String
  if and(gt(prim_len(a), 0), and(not(is_some(str_find(a, " "))), not(is_some(str_find(a, "\""))))) then a
  else str_join(["\"", str_join(str_split(a, "\""), "\\\""), "\""], "")
  end
end

fn os_env_get(name: String) -> Option[String]
  let buf = prim_str_new(32768)
  let n = prim_ccall32("GetEnvironmentVariableA", [prim_addr(cstr(name)), prim_addr(buf), 32768])
  if or(le(n, 0), ge(n, 32768)) then None else Some(str_slice(buf, 0, n)) end
end

fn os_exit(code: Int) -> Unit
  prim_ccall("ExitProcess", [code])
  Unit
end

# ---------- console ----------

fn os_term_raw() -> Result[String, String]
  let m_in = zeros(8)
  let m_out = zeros(8)
  if eq(prim_ccall32("GetConsoleMode", [h_in, prim_addr(m_in)]), 0) then Err("stdin is not a console") else
    prim_ccall32("GetConsoleMode", [h_out, prim_addr(m_out)])
    let saved = str_from_bytes(list_concat(list_slice(bytes_of(m_in), 0, 4), list_slice(bytes_of(m_out), 0, 4)))
    let in_mode = u_le(m_in, 0, 4)
    prim_ccall32("SetConsoleMode", [h_in, sub(in_mode, bit_and(in_mode, 6))])
    prim_ccall32("SetConsoleMode", [h_out, bit_or(u_le(m_out, 0, 4), 5)])
    Ok(saved)
  end
end

fn bytes_of(s: String) -> List[Int]
  list_map(list_range(0, prim_len(s)), fn(i) prim_byte(s, i) end)
end

fn os_term_set(saved: String) -> Unit
  prim_ccall32("SetConsoleMode", [h_in, u_le(saved, 0, 4)])
  prim_ccall32("SetConsoleMode", [h_out, u_le(saved, 4, 4)])
  Unit
end

# pending key presses as bytes; arrow keys become ESC [ A..D like on a VT terminal
fn os_term_read() -> String
  term_events("")
end

fn term_events(acc: String) -> String
  let cnt = zeros(8)
  prim_ccall32("GetNumberOfConsoleInputEvents", [h_in, prim_addr(cnt)])
  if eq(u_le(cnt, 0, 4), 0) then acc else
    let rec = zeros(24)
    let got = zeros(8)
    prim_ccall32("ReadConsoleInputA", [h_in, prim_addr(rec), 1, prim_addr(got)])
    let key = and(eq(u_le(rec, 0, 2), 1), ne(u_le(rec, 4, 4), 0))
    if not(key) then term_events(acc) else
      let vk = u_le(rec, 10, 2)
      let ch = prim_byte(rec, 14)
      let s = match vk
        case 38 -> "\e[A"
        case 40 -> "\e[B"
        case 39 -> "\e[C"
        case 37 -> "\e[D"
        case _ -> if eq(ch, 0) then "" else str_from_bytes([ch]) end
      end
      term_events(str_cat(acc, s))
    end
  end
end

# ---------- time ----------

fn os_now_ms() -> Int
  let ft = zeros(8)
  prim_ccall("GetSystemTimeAsFileTime", [prim_addr(ft)])
  sub(div(u_le(ft, 0, 8), 10000), 11644473600000)
end

fn os_sleep_ms(n: Int) -> Unit
  prim_ccall("Sleep", [max(0, n)])
  Unit
end

# ---------- net (winsock) ----------

fn wsa_error() -> Int
  sub(0, prim_ccall32("ws2_32.dll!WSAGetLastError", []))
end

fn os_tcp_listen(addr: String) -> Result[Int, String]
  match sockaddr(addr, false)
    case None -> Err(str_cat("bad address (want ip:port): ", addr))
    case Some(sa) ->
      let s = prim_ccall("ws2_32.dll!socket", [2, 1, 6])
      if eq(s, -1) then Err(os_errmsg(wsa_error())) else
        if ne(prim_ccall32("ws2_32.dll!bind", [s, prim_addr(sa), 16]), 0) then
          let e = wsa_error()
          prim_ccall32("ws2_32.dll!closesocket", [s])
          Err(str_join(["listen tcp ", addr, ": bind: ", os_errmsg(e)], ""))
        elif ne(prim_ccall32("ws2_32.dll!listen", [s, 128]), 0) then Err(os_errmsg(wsa_error()))
        else Ok(s) end
      end
  end
end

fn os_unix_connect(path: String) -> Result[Int, String]
  Err("unix sockets are not supported on Windows")
end

fn os_tcp_accept(l: Int) -> Result[Int, String]
  let c = prim_ccall("ws2_32.dll!accept", [l, 0, 0])
  if eq(c, -1) then Err(os_errmsg(wsa_error())) else Ok(c) end
end

fn os_tcp_read(c: Int, n: Int, timeout: Int) -> Result[String, String]
  let tv = zeros(8)
  put_le(tv, 0, max(1, timeout), 4)
  prim_ccall32("ws2_32.dll!setsockopt", [c, 0xFFFF, 0x1006, prim_addr(tv), 4])
  let buf = prim_str_new(n)
  let r = prim_ccall32("ws2_32.dll!recv", [c, prim_addr(buf), n, 0])
  if lt(r, 0) then Err(os_errmsg(wsa_error())) else Ok(str_slice(buf, 0, r)) end
end

fn send_all(c: Int, s: String, off: Int) -> Int
  let n = prim_len(s)
  if ge(off, n) then 0 else
    let w = prim_ccall32("ws2_32.dll!send", [c, add(prim_addr(s), off), sub(n, off), 0])
    if lt(w, 0) then wsa_error() else send_all(c, s, add(off, w)) end
  end
end

fn os_tcp_write(c: Int, s: String) -> Result[Unit, String]
  let r = send_all(c, s, 0)
  if lt(r, 0) then Err(os_errmsg(r)) else Ok(Unit) end
end

fn os_tcp_close(c: Int) -> Unit
  prim_ccall32("ws2_32.dll!closesocket", [c])
  Unit
end

# ---------- files ----------

fn read_handle(h: Int, acc: List[String]) -> Result[String, String]
  let buf = prim_str_new(65536)
  let got = zeros(8)
  if eq(prim_ccall32("ReadFile", [h, prim_addr(buf), 65536, prim_addr(got), 0]), 0) then Err(win_errmsg(last_error())) else
    let n = u_le(got, 0, 4)
    if eq(n, 0) then Ok(str_join(acc, "")) else read_handle(h, list_push(acc, str_slice(buf, 0, n))) end
  end
end

# all of standard input in 64 KiB reads; an error (a closed pipe) counts as the end
fn os_read_stdin(acc: List[String]) -> String
  let buf = prim_str_new(65536)
  let got = zeros(8)
  let ok = prim_ccall32("ReadFile", [h_in, prim_addr(buf), 65536, prim_addr(got), 0])
  let n = u_le(got, 0, 4)
  if or(eq(ok, 0), eq(n, 0)) then str_join(acc, "") else os_read_stdin(list_push(acc, str_slice(buf, 0, n))) end
end

fn os_read_file(path: String) -> Result[String, String]
  let h = prim_ccall("CreateFileA", [prim_addr(cstr(path)), 0x80000000, 1, 0, 3, 128, 0])
  if eq(h, -1) then Err(str_join(["open ", path, ": ", win_errmsg(last_error())], "")) else
    let r = read_handle(h, [])
    prim_ccall32("CloseHandle", [h])
    r
  end
end

fn os_write_file(path: String, content: String, mode_bits: Int) -> Result[Unit, String]
  let h = prim_ccall("CreateFileA", [prim_addr(cstr(path)), 0x40000000, 0, 0, 2, 128, 0])
  if eq(h, -1) then Err(str_join(["open ", path, ": ", win_errmsg(last_error())], "")) else
    let w = write_handle(h, content, 0)
    prim_ccall32("CloseHandle", [h])
    if lt(w, 0) then Err(os_errmsg(w)) else Ok(Unit) end
  end
end

fn find_loop(h: Int, data: String, acc: List[String]) -> List[String]
  let name = cstring_at(add(prim_addr(data), 44))
  let acc2 = if or(eq(name, "."), eq(name, "..")) then acc else list_push(acc, name) end
  if eq(prim_ccall32("FindNextFileA", [h, prim_addr(data)]), 0) then acc2 else find_loop(h, data, acc2) end
end

fn os_list_dir(path: String) -> Result[List[String], String]
  let data = zeros(592)
  let h = prim_ccall("FindFirstFileA", [prim_addr(cstr(str_cat(path, "/*"))), prim_addr(data)])
  if eq(h, -1) then Err(str_join(["open ", path, ": ", win_errmsg(last_error())], "")) else
    let names = find_loop(h, data, [])
    prim_ccall32("FindClose", [h])
    Ok(names)
  end
end

# ---------- processes ----------

# runs exe with the command line, waits, returns its exit code (or -1 if it could not start)
fn spawn_wait(exe: String, cmdline: String) -> Int
  let si = zeros(104)
  put_le(si, 0, 104, 4)
  let pi = zeros(24)
  let ok = prim_ccall32("CreateProcessA", [prim_addr(cstr(exe)), prim_addr(cstr(cmdline)), 0, 0, 1, 0, 0, 0, prim_addr(si), prim_addr(pi)])
  if eq(ok, 0) then -1 else
    let hp = u_le(pi, 0, 8)
    prim_ccall32("WaitForSingleObject", [hp, 0xFFFFFFFF])
    let code = zeros(8)
    prim_ccall32("GetExitCodeProcess", [hp, prim_addr(code)])
    prim_ccall32("CloseHandle", [hp])
    prim_ccall32("CloseHandle", [u_le(pi, 8, 8)])
    u_le(code, 0, 4)
  end
end

fn self_path() -> String
  let buf = prim_str_new(1024)
  let n = prim_ccall32("GetModuleFileNameA", [0, prim_addr(buf), 1024])
  str_slice(buf, 0, n)
end

fn os_run_image(bin: String, argv: List[String]) -> Result[Unit, String]
  let dir = prim_str_new(300)
  let n = prim_ccall32("GetTempPathA", [300, prim_addr(dir)])
  let exe = str_join([str_slice(dir, 0, n), "kaizo-run-", show(prim_ccall32("GetCurrentProcessId", [])), ".exe"], "")
  match os_write_file(exe, bin, 493)
    case Err(e) -> Err(e)
    case Ok(_) ->
      let code = spawn_wait(exe, str_join(list_map(list_cons(exe, argv), quote_arg), " "))
      prim_ccall32("DeleteFileA", [prim_addr(cstr(exe))])
      if lt(code, 0) then Err(str_cat("cannot start ", exe)) else
        os_exit(code)
        Ok(Unit)
      end
  end
end

fn os_test_mode() -> Option[Int]
  match os_args()
    case ["--kaizo-test", i] -> str_to_int(i)
    case _ -> None
  end
end

# runs test i in a child process (the test binary itself with --kaizo-test i)
fn os_test_child(fns: List[Fn() -> Unit], i: Int) -> Int
  let exe = self_path()
  let code = spawn_wait(exe, str_join([quote_arg(exe), "--kaizo-test", show(i)], " "))
  if or(lt(code, 0), gt(code, 255)) then 1011 else code end
end
