# OS layer: Linux x86-64, raw syscalls (no libc).

fn sys(n: Int, a: Int, b: Int, c: Int) -> Int
  prim_syscall(n, a, b, c, 0, 0, 0)
end

fn sys5(n: Int, a: Int, b: Int, c: Int, d: Int, e: Int) -> Int
  prim_syscall(n, a, b, c, d, e, 0)
end

fn os_errmsg(r: Int) -> String
  match sub(0, r)
    case 2 -> "no such file or directory"
    case 9 -> "bad file descriptor"
    case 11 -> "resource temporarily unavailable"
    case 13 -> "permission denied"
    case 17 -> "file exists"
    case 20 -> "not a directory"
    case 21 -> "is a directory"
    case 32 -> "broken pipe"
    case 98 -> "address already in use"
    case 99 -> "cannot assign requested address"
    case 104 -> "connection reset by peer"
    case 110 -> "i/o timeout"
    case e -> str_cat("errno ", show(e))
  end
end

fn os_write(fd: Int, s: String) -> Int
  write_fd(fd, s, 0)
end

fn write_fd(fd: Int, s: String, off: Int) -> Int
  let n = prim_len(s)
  if ge(off, n) then 0 else
    let w = sys(1, fd, add(prim_addr(s), off), sub(n, off))
    if lt(w, 0) then w else write_fd(fd, s, add(off, w)) end
  end
end

fn os_read_byte() -> Int
  let buf = zeros(1)
  if le(sys(0, 0, prim_addr(buf), 1), 0) then -1 else prim_byte(buf, 0) end
end

fn os_args() -> List[String]
  posix_args()
end

fn os_env_get(name: String) -> Option[String]
  posix_env_get(name)
end

fn os_exit(code: Int) -> Unit
  sys(231, code, 0, 0)
  Unit
end

# ---------- terminal ----------

fn os_term_raw() -> Result[String, String]
  let t = zeros(64)
  let r = sys(16, 0, 0x5401, prim_addr(t))
  if lt(r, 0) then Err(str_cat("stdin is not a terminal: ", os_errmsg(r))) else
    let saved = str_slice(t, 0, 64)
    let lf = prim_byte(t, 12)
    prim_set_byte(t, 12, sub(sub(lf, if has_bit(lf, 2) then 2 else 0 end), if has_bit(lf, 8) then 8 else 0 end))
    prim_set_byte(t, 22, 0)
    prim_set_byte(t, 23, 0)
    let r2 = sys(16, 0, 0x5402, prim_addr(t))
    if lt(r2, 0) then Err(os_errmsg(r2)) else Ok(saved) end
  end
end

fn os_term_set(saved: String) -> Unit
  sys(16, 0, 0x5402, prim_addr(saved))
  Unit
end

fn os_term_read() -> String
  let buf = zeros(64)
  let n = sys(0, 0, prim_addr(buf), 64)
  if gt(n, 0) then str_slice(buf, 0, n) else "" end
end

# ---------- time ----------

fn os_now_ms() -> Int
  let ts = zeros(16)
  sys(228, 0, prim_addr(ts), 0)
  add(mul(u_le(ts, 0, 8), 1000), div(u_le(ts, 8, 8), 1000000))
end

fn os_sleep_ms(n: Int) -> Unit
  let ts = zeros(16)
  put_le(ts, 0, div(max(0, n), 1000), 8)
  put_le(ts, 8, mul(mod(max(0, n), 1000), 1000000), 8)
  sys(35, prim_addr(ts), 0, 0)
  Unit
end

# ---------- net ----------

fn os_tcp_listen(addr: String) -> Result[Int, String]
  match sockaddr(addr, false)
    case None -> Err(str_cat("bad address (want ip:port): ", addr))
    case Some(sa) ->
      let fd = sys(41, 2, 0x80001, 0)
      if lt(fd, 0) then Err(os_errmsg(fd)) else
        let one = str_from_bytes([1, 0, 0, 0])
        sys5(54, fd, 1, 2, prim_addr(one), 4)
        let r = sys(49, fd, prim_addr(sa), 16)
        if lt(r, 0) then
          sys(3, fd, 0, 0)
          Err(str_join(["listen tcp ", addr, ": bind: ", os_errmsg(r)], ""))
        else
          let r2 = sys(50, fd, 128, 0)
          if lt(r2, 0) then Err(os_errmsg(r2)) else Ok(fd) end
        end
      end
  end
end

fn os_unix_connect(path: String) -> Result[Int, String]
  let fd = sys(41, 1, 524289, 0)
  if lt(fd, 0) then Err(os_errmsg(fd)) else
    let sa = zeros(110)
    put_le(sa, 0, 1, 2)
    prim_copy(sa, 2, path, 0, min(prim_len(path), 107))
    let r = sys(42, fd, prim_addr(sa), 110)
    if lt(r, 0) then
      sys(3, fd, 0, 0)
      Err(str_join(["connect ", path, ": ", os_errmsg(r)], ""))
    else Ok(fd) end
  end
end

fn os_tcp_accept(l: Int) -> Result[Int, String]
  let fd = sys(43, l, 0, 0)
  if lt(fd, 0) then Err(os_errmsg(fd)) else Ok(fd) end
end

fn os_tcp_read(fd: Int, n: Int, timeout: Int) -> Result[String, String]
  let pfd = zeros(8)
  put_le(pfd, 0, fd, 4)
  put_le(pfd, 4, 1, 2)
  let pr = sys(7, prim_addr(pfd), 1, timeout)
  if lt(pr, 0) then Err(os_errmsg(pr))
  elif eq(pr, 0) then Err("i/o timeout")
  else
    let buf = prim_str_new(n)
    let r = sys(0, fd, prim_addr(buf), n)
    if lt(r, 0) then Err(os_errmsg(r)) else Ok(str_slice(buf, 0, r)) end
  end
end

fn os_tcp_write(fd: Int, s: String) -> Result[Unit, String]
  let r = write_fd(fd, s, 0)
  if lt(r, 0) then Err(os_errmsg(r)) else Ok(Unit) end
end

fn os_tcp_close(fd: Int) -> Unit
  sys(3, fd, 0, 0)
  Unit
end

# ---------- files ----------

fn read_chunks(fd: Int, acc: List[String]) -> Result[String, String]
  let buf = prim_str_new(65536)
  let n = sys(0, fd, prim_addr(buf), 65536)
  if lt(n, 0) then Err(os_errmsg(n))
  elif eq(n, 0) then Ok(str_join(acc, ""))
  else read_chunks(fd, list_push(acc, str_slice(buf, 0, n)))
  end
end

# all of standard input in 64 KiB reads; an error counts as the end
fn os_read_stdin(acc: List[String]) -> String
  let buf = prim_str_new(65536)
  let n = sys(0, 0, prim_addr(buf), 65536)
  if le(n, 0) then str_join(acc, "") else os_read_stdin(list_push(acc, str_slice(buf, 0, n))) end
end

fn os_read_file(path: String) -> Result[String, String]
  let fd = sys(2, prim_addr(cstr(path)), 0, 0)
  if lt(fd, 0) then Err(str_join(["open ", path, ": ", os_errmsg(fd)], "")) else
    let r = read_chunks(fd, [])
    sys(3, fd, 0, 0)
    r
  end
end

fn os_write_file(path: String, content: String, mode_bits: Int) -> Result[Unit, String]
  let fd = sys(2, prim_addr(cstr(path)), 0x241, mode_bits)
  if lt(fd, 0) then Err(str_join(["open ", path, ": ", os_errmsg(fd)], "")) else
    let w = write_fd(fd, content, 0)
    sys(91, fd, mode_bits, 0)
    sys(3, fd, 0, 0)
    if lt(w, 0) then Err(os_errmsg(w)) else Ok(Unit) end
  end
end

fn dirents(buf: String, off: Int, n: Int, acc: List[String]) -> List[String]
  if ge(off, n) then acc else
    let reclen = u_le(buf, add(off, 16), 2)
    let name = cstring_at(add(prim_addr(buf), add(off, 19)))
    let acc2 = if or(eq(name, "."), eq(name, "..")) then acc else list_push(acc, name) end
    dirents(buf, add(off, reclen), n, acc2)
  end
end

fn read_dir(fd: Int, acc: List[String]) -> Result[List[String], String]
  let buf = prim_str_new(32768)
  let n = sys(217, fd, prim_addr(buf), 32768)
  if lt(n, 0) then Err(os_errmsg(n))
  elif eq(n, 0) then Ok(acc)
  else read_dir(fd, dirents(buf, 0, n, acc))
  end
end

fn os_list_dir(path: String) -> Result[List[String], String]
  let fd = sys(2, prim_addr(cstr(path)), 0x10000, 0)
  if lt(fd, 0) then Err(str_join(["open ", path, ": ", os_errmsg(fd)], "")) else
    let r = read_dir(fd, [])
    sys(3, fd, 0, 0)
    r
  end
end

# ---------- processes ----------

fn os_run_image(bin: String, argv: List[String]) -> Result[Unit, String]
  let fd = sys(319, prim_addr(cstr("kaizo-app")), 0, 0)
  if lt(fd, 0) then Err(str_cat("memfd_create: ", os_errmsg(fd))) else
    write_fd(fd, bin, 0)
    let av = ptr_array(list_map(list_cons("app", argv), cstr))
    let r = prim_syscall(322, fd, prim_addr(cstr("")), prim_addr(av), prim_envp(), 4096, 0)
    Err(str_cat("execveat: ", os_errmsg(r)))
  end
end

fn os_test_mode() -> Option[Int]
  None
end

# runs test i in a forked child; 0 = passed, 1..255 = exit code, 1000 + n = killed by signal n
fn os_test_child(fns: List[Fn() -> Unit], i: Int) -> Int
  let pid = sys(57, 0, 0, 0)
  if eq(pid, 0) then
    let f = prim_slot(fns, i)
    f()
    sys(231, 0, 0, 0)
    0
  else
    let st = zeros(8)
    sys5(61, pid, prim_addr(st), 0, 0, 0)
    let sig = mod(prim_byte(st, 0), 128)
    if ne(sig, 0) then add(1000, sig) else prim_byte(st, 1) end
  end
end
