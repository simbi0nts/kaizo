# Mach-O executable for macOS (x86-64 and arm64): __TEXT (R-X), __DATA (RW-, includes the GOT that
# dyld binds to libSystem), __LINKEDIT (bind opcodes, empty symbol table, ad-hoc code signature).
# The image is position independent; start-up self-relocation adds the ASLR slide to data pointers.

import sha256

let macho_base = 4294967296
let macho_page = 16384

fn name16(s: String) -> List[Int]
  let b = list_map(list_range(0, str_len(s)), fn(i) str_byte(s, i) end)
  list_concat(b, lebytes(0, sub(16, list_len(b))))
end

fn uleb(n: Int) -> List[Int]
  if lt(n, 128) then [n] else list_cons(add(128, mod(n, 128)), uleb(div(n, 128))) end
end

fn segment(name: String, vmaddr: Int, vmsize: Int, fileoff: Int, filesize: Int, prot: Int, sections: List[List[Int]]) -> List[Int]
  let n = list_len(sections)
  le_all(list_concat([lebytes(25, 4), lebytes(add(72, mul(80, n)), 4), name16(name), lebytes(vmaddr, 8), lebytes(vmsize, 8), lebytes(fileoff, 8), lebytes(filesize, 8),
    lebytes(prot, 4), lebytes(prot, 4), lebytes(n, 4), lebytes(0, 4)], sections))
end

fn section(sect: String, seg: String, addr: Int, size: Int, off: Int, align_log: Int, flags: Int) -> List[Int]
  le_all([name16(sect), name16(seg), lebytes(addr, 8), lebytes(size, 8), lebytes(off, 4), lebytes(align_log, 4), lebytes(0, 8), lebytes(flags, 4), lebytes(0, 12)])
end

fn lc(cmd: Int, body: List[Int]) -> List[Int]
  le_all([lebytes(cmd, 4), lebytes(add(8, list_len(body)), 4), body])
end

fn cstr_padded(s: String, total: Int) -> List[Int]
  let b = list_map(list_range(0, str_len(s)), fn(i) str_byte(s, i) end)
  list_concat(b, lebytes(0, sub(total, list_len(b))))
end

fn bind_info(syms: List[String], l: LinkOut) -> List[Int]
  let body = list_fold(syms, [17], fn(acc, s)
    let off = sub(sym_addr(l, imp_label(s)), l.data_addr)
    le_all([acc, [64], cstr_padded(str_cat("_", s), add(str_len(s), 2)), [81, 114], uleb(off), [144]])
  end)
  let all = list_push(body, 0)
  list_concat(all, lebytes(0, sub(align_up(list_len(all), 8), list_len(all))))
end

fn be(v: Int, k: Int) -> List[Int]
  sha256.be_bytes(v, k)
end

# ad-hoc, linker-style code signature: SuperBlob with one CodeDirectory hashing every 4 KiB page
fn code_signature(file: String, ident: String, text_size: Int) -> String
  let limit = str_len(file)
  let slots = div(add(limit, 4095), 4096)
  let id_bytes = cstr_padded(ident, add(str_len(ident), 1))
  let hash_off = add(88, list_len(id_bytes))
  let cd_len = add(hash_off, mul(32, slots))
  let cd_head = le_all([be(4208856066, 4), be(cd_len, 4), be(132096, 4), be(131074, 4), be(hash_off, 4), be(88, 4), be(0, 4), be(slots, 4), be(limit, 4),
    [32, 2, 0, 12], be(0, 4), be(0, 4), be(0, 4), be(0, 4), be(0, 8), be(0, 8), be(text_size, 8), be(1, 8), id_bytes])
  let hashes = list_map(list_range(0, slots), fn(i) sha256.digest(str_slice(file, mul(i, 4096), min(limit, mul(add(i, 1), 4096)))) end)
  let super = le_all([be(4208856256, 4), be(add(20, cd_len), 4), be(1, 4), be(0, 4), be(20, 4)])
  str_join(list_concat([str_from_bytes(super), str_from_bytes(cd_head)], hashes), "")
end

fn sig_size(limit: Int, ident: String) -> Int
  add(add(20, add(88, add(str_len(ident), 1))), mul(32, div(add(limit, 4095), 4096)))
end

fn write_macho(t: Target, o: Out) -> Image
  let syms = list_fold(o.imports, [], fn(acc, s) if list_contains(acc, import_sym(s)) then acc else list_push(acc, import_sym(s)) end end)
  let got = assemble(t, cat(list_concat([CLab("got")], list_map(syms, fn(s) CCat(CLab(imp_label(s)), CB(lebytes(0, 8))) end))))
  let l = link_regions(o.text, list_push(o.data, got), add(macho_base, 4096), macho_page, 0)
  let text_seg = sub(l.data_addr, macho_base)
  let data_off = text_seg
  let data_seg = align_up(max(1, str_len(l.data)), macho_page)
  let le_off = add(data_off, data_seg)
  let bind = bind_info(syms, l)
  let str_off = add(le_off, list_len(bind))
  let sig_off = align_up(add(str_off, 8), 16)
  let ident = "kaizo.app"
  let sig_len = sig_size(sig_off, ident)
  let le_size = sub(add(sig_off, sig_len), le_off)
  let cpu = if eq(t.arch, "arm64") then [lebytes(16777228, 4), lebytes(0, 4)] else [lebytes(16777223, 4), lebytes(3, 4)] end
  let uuid = list_map(list_range(0, 16), fn(i) str_byte(sha256.digest(str_slice(l.text, 0, min(str_len(l.text), 65536))), i) end)
  let cmds = [
    segment("__PAGEZERO", 0, macho_base, 0, 0, 0, []),
    segment("__TEXT", macho_base, text_seg, 0, text_seg, 5, [section("__text", "__TEXT", l.text_addr, str_len(l.text), 4096, 4, 2147484672)]),
    segment("__DATA", l.data_addr, data_seg, data_off, data_seg, 3, [section("__data", "__DATA", l.data_addr, str_len(l.data), data_off, 3, 0)]),
    segment("__LINKEDIT", add(l.data_addr, data_seg), align_up(le_size, macho_page), le_off, le_size, 1, []),
    lc(2147483682, le_all([lebytes(0, 8), lebytes(le_off, 4), lebytes(list_len(bind), 4), lebytes(0, 24)])),
    lc(2, le_all([lebytes(str_off, 4), lebytes(0, 4), lebytes(str_off, 4), lebytes(8, 4)])),
    lc(11, lebytes(0, 72)),
    lc(14, list_concat(lebytes(12, 4), cstr_padded("/usr/lib/dyld", 20))),
    lc(27, uuid),
    lc(50, le_all([lebytes(1, 4), lebytes(720896, 4), lebytes(720896, 4), lebytes(0, 4)])),
    lc(2147483688, le_all([lebytes(sub(sym_addr(l, "_start"), macho_base), 8), lebytes(0, 8)])),
    lc(12, le_all([lebytes(24, 4), lebytes(2, 4), lebytes(84698117, 4), lebytes(65536, 4), cstr_padded("/usr/lib/libSystem.B.dylib", 32)])),
    lc(29, le_all([lebytes(sig_off, 4), lebytes(sig_len, 4)]))
  ]
  let body = le_all(cmds)
  let header = le_all(list_concat(list_concat([lebytes(4277009103, 4)], cpu), [lebytes(2, 4), lebytes(list_len(cmds), 4), lebytes(list_len(body), 4), lebytes(2097285, 4), lebytes(0, 4)]))
  let head = str_from_bytes(list_concat(header, body))
  let file = join_all(strs_from([head, zeros_str(sub(4096, str_len(head))), l.text, zeros_str(sub(data_off, add(4096, str_len(l.text)))),
    l.data, zeros_str(sub(data_seg, str_len(l.data))), str_from_bytes(bind), str_from_bytes([32, 0, 0, 0, 0, 0, 0, 0]),
    zeros_str(sub(sig_off, add(str_off, 8)))]))
  Image { bytes: str_cat(file, code_signature(file, ident, text_seg)), missing: l.missing }
end
