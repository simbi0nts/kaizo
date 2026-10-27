# macOS x86-64: the 64-bit-inode variants of the directory functions.

fn os_opendir(p: String) -> Int
  prim_ccall("opendir$INODE64", [prim_addr(cstr(p))])
end

fn os_readdir(d: Int) -> Int
  prim_ccall("readdir$INODE64", [d])
end
