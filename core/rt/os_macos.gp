# OS layer: macOS (x86-64 and arm64), via libSystem (dyld binds the symbols at load time).
# Variadic C functions are avoided on purpose (arm64 passes variadic arguments on the stack).

fn errno() -> Int
  bit_and(prim_peek(prim_ccall("__error", [])), 4294967295)
end

fn os_errmsg(r: Int) -> String
  cstring_at(prim_ccall("strerror", [sub(0, r)]))
end

fn neg_errno(r: Int) -> Int
  if lt(r, 0) then sub(0, errno()) else r end
end

fn os_write(fd: Int, s: String) -> Int
  write_fd(fd, s, 0)
end

fn write_fd(fd: Int, s: String, off: Int) -> Int
  let n = prim_len(s)
  if ge(off, n) then 0 else
    let w = neg_errno(prim_ccall("write", [fd, add(prim_addr(s), off), sub(n, off)]))
    if lt(w, 0) then w else write_fd(fd, s, add(off, w)) end
  end
end

fn os_read_byte() -> Int
  let buf = zeros(1)
  if le(prim_ccall("read", [0, prim_addr(buf), 1]), 0) then -1 else prim_byte(buf, 0) end
end

fn os_args() -> List[String]
  posix_args()
end

fn os_env_get(name: String) -> Option[String]
  posix_env_get(name)
end

fn os_exit(code: Int) -> Unit
  prim_ccall("exit", [code])
  Unit
end

# ---------- terminal (struct termios: 4 x 8-byte flags, c_cc[20] at 32) ----------

fn os_term_raw() -> Result[String, String]
  let t = zeros(80)
  let r = neg_errno(prim_ccall32("tcgetattr", [0, prim_addr(t)]))
  if lt(r, 0) then Err(str_cat("stdin is not a terminal: ", os_errmsg(r))) else
    let saved = str_slice(t, 0, 80)
    prim_set_byte(t, 24, sub(prim_byte(t, 24), bit_and(prim_byte(t, 24), 8)))
    prim_set_byte(t, 25, sub(prim_byte(t, 25), bit_and(prim_byte(t, 25), 1)))
    prim_set_byte(t, 48, 0)
    prim_set_byte(t, 49, 0)
    let r2 = neg_errno(prim_ccall32("tcsetattr", [0, 0, prim_addr(t)]))
    if lt(r2, 0) then Err(os_errmsg(r2)) else Ok(saved) end
  end
end

fn os_term_set(saved: String) -> Unit
  prim_ccall32("tcsetattr", [0, 0, prim_addr(saved)])
  Unit
end

fn os_term_read() -> String
  let buf = zeros(64)
  let n = prim_ccall("read", [0, prim_addr(buf), 64])
  if gt(n, 0) then str_slice(buf, 0, n) else "" end
end

# ---------- time ----------

fn os_now_ms() -> Int
  let ts = zeros(16)
  prim_ccall32("clock_gettime", [0, prim_addr(ts)])
  add(mul(u_le(ts, 0, 8), 1000), div(u_le(ts, 8, 8), 1000000))
end

fn os_sleep_ms(n: Int) -> Unit
  let ts = zeros(16)
  put_le(ts, 0, div(max(0, n), 1000), 8)
  put_le(ts, 8, mul(mod(max(0, n), 1000), 1000000), 8)
  prim_ccall32("nanosleep", [prim_addr(ts), 0])
  Unit
end

# ---------- net ----------

fn os_tcp_listen(addr: String) -> Result[Int, String]
  match sockaddr(addr, true)
    case None -> Err(str_cat("bad address (want ip:port): ", addr))
    case Some(sa) ->
      let fd = neg_errno(prim_ccall32("socket", [2, 1, 0]))
      if lt(fd, 0) then Err(os_errmsg(fd)) else
        let one = str_from_bytes([1, 0, 0, 0])
        prim_ccall32("setsockopt", [fd, 65535, 4, prim_addr(one), 4])
        let r = neg_errno(prim_ccall32("bind", [fd, prim_addr(sa), 16]))
        if lt(r, 0) then
          prim_ccall32("close", [fd])
          Err(str_join(["listen tcp ", addr, ": bind: ", os_errmsg(r)], ""))
        else
          let r2 = neg_errno(prim_ccall32("listen", [fd, 128]))
          if lt(r2, 0) then Err(os_errmsg(r2)) else Ok(fd) end
        end
      end
  end
end

fn os_tcp_accept(l: Int) -> Result[Int, String]
  let fd = neg_errno(prim_ccall32("accept", [l, 0, 0]))
  if lt(fd, 0) then Err(os_errmsg(fd)) else Ok(fd) end
end

fn os_tcp_read(fd: Int, n: Int, timeout: Int) -> Result[String, String]
  let pfd = zeros(8)
  put_le(pfd, 0, fd, 4)
  put_le(pfd, 4, 1, 2)
  let pr = neg_errno(prim_ccall32("poll", [prim_addr(pfd), 1, timeout]))
  if lt(pr, 0) then Err(os_errmsg(pr))
  elif eq(pr, 0) then Err("i/o timeout")
  else
    let buf = prim_str_new(n)
    let r = neg_errno(prim_ccall("read", [fd, prim_addr(buf), n]))
    if lt(r, 0) then Err(os_errmsg(r)) else Ok(str_slice(buf, 0, r)) end
  end
end

fn os_tcp_write(fd: Int, s: String) -> Result[Unit, String]
  let r = write_fd(fd, s, 0)
  if lt(r, 0) then Err(os_errmsg(r)) else Ok(Unit) end
end

fn os_tcp_close(fd: Int) -> Unit
  prim_ccall32("close", [fd])
  Unit
end

# ---------- files ----------

fn read_chunks(fd: Int, acc: List[String]) -> Result[String, String]
  let buf = prim_str_new(65536)
  let n = neg_errno(prim_ccall("read", [fd, prim_addr(buf), 65536]))
  if lt(n, 0) then Err(os_errmsg(n))
  elif eq(n, 0) then Ok(str_join(acc, ""))
  else read_chunks(fd, list_push(acc, str_slice(buf, 0, n)))
  end
end

fn os_read_file(path: String) -> Result[String, String]
  let fd = neg_errno(prim_ccall32("open", [prim_addr(cstr(path)), 0]))
  if lt(fd, 0) then Err(str_join(["open ", path, ": ", os_errmsg(fd)], "")) else
    let r = read_chunks(fd, [])
    prim_ccall32("close", [fd])
    r
  end
end

fn os_write_file(path: String, content: String, mode_bits: Int) -> Result[Unit, String]
  let fd = neg_errno(prim_ccall32("creat", [prim_addr(cstr(path)), mode_bits]))
  if lt(fd, 0) then Err(str_join(["open ", path, ": ", os_errmsg(fd)], "")) else
    let w = write_fd(fd, content, 0)
    prim_ccall32("fchmod", [fd, mode_bits])
    prim_ccall32("close", [fd])
    if lt(w, 0) then Err(os_errmsg(w)) else Ok(Unit) end
  end
end

# struct dirent (64-bit inodes): d_name at offset 21
fn readdir_loop(d: Int, acc: List[String]) -> List[String]
  let e = os_readdir(d)
  if eq(e, 0) then acc else
    let name = cstring_at(add(e, 21))
    readdir_loop(d, if or(eq(name, "."), eq(name, "..")) then acc else list_push(acc, name) end)
  end
end

fn os_list_dir(path: String) -> Result[List[String], String]
  let d = os_opendir(path)
  if eq(d, 0) then Err(str_join(["open ", path, ": ", os_errmsg(sub(0, errno()))], "")) else
    let names = readdir_loop(d, [])
    prim_ccall32("closedir", [d])
    Ok(names)
  end
end

# ---------- processes ----------

fn wait_child(pid: Int) -> Int
  let st = zeros(8)
  prim_ccall32("waitpid", [pid, prim_addr(st), 0])
  let sig = bit_and(prim_byte(st, 0), 127)
  if ne(sig, 0) then add(1000, sig) else prim_byte(st, 1) end
end

fn os_run_image(bin: String, argv: List[String]) -> Result[Unit, String]
  let path = str_join(["/tmp/kaizo-run-", show(prim_ccall32("getpid", [])), "-", show(os_now_ms())], "")
  match os_write_file(path, bin, 493)
    case Err(e) -> Err(e)
    case Ok(_) ->
      let pid = prim_ccall32("fork", [])
      if eq(pid, 0) then
        let av = ptr_array(list_map(list_cons(path, argv), cstr))
        prim_ccall32("execve", [prim_addr(cstr(path)), prim_addr(av), prim_envp()])
        prim_ccall("_exit", [127])
        Ok(Unit)
      else
        let code = wait_child(pid)
        prim_ccall32("unlink", [prim_addr(cstr(path))])
        os_exit(if ge(code, 1000) then add(128, sub(code, 1000)) else code end)
        Ok(Unit)
      end
  end
end

fn os_test_mode() -> Option[Int]
  None
end

fn os_test_child(fns: List[Fn() -> Unit], i: Int) -> Int
  let pid = prim_ccall32("fork", [])
  if eq(pid, 0) then
    let f = prim_slot(fns, i)
    f()
    prim_ccall("exit", [0])
    0
  else wait_child(pid) end
end
