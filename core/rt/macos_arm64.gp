# macOS arm64: directory functions (64-bit inodes are the only variant).

fn os_opendir(p: String) -> Int
  prim_ccall("opendir", [prim_addr(cstr(p))])
end

fn os_readdir(d: Int) -> Int
  prim_ccall("readdir", [d])
end
