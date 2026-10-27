# PE32+ executable for Windows x64: .text (R-X) + .data (RW-, includes the import tables).
# Fixed image base, no relocations needed (code is position independent; data pointers are linked
# for the image base and the start-up self-relocation sees a zero slide).

let pe_base = 0x140000000
let pe_file_align = 512

type Dll = { name: String, syms: List[String] } end

# "dll!sym" -> (dll, sym); a plain sym lives in kernel32
fn dll_of(s: String) -> String
  match str_find(s, "!")
    case Some(i) -> str_lower(str_slice(s, 0, i))
    case None -> "kernel32.dll"
  end
end

fn group_dlls(imports: List[String]) -> List[Dll]
  list_fold(imports, [], fn(acc, imp)
    let d = dll_of(imp)
    let sym = import_sym(imp)
    if list_contains(list_map(acc, fn(x) x.name end), d) then
      list_map(acc, fn(x) if and(eq(x.name, d), not(list_contains(x.syms, sym))) then { x with syms: list_push(x.syms, sym) } else x end end)
    else list_push(acc, Dll { name: d, syms: [sym] }) end
  end)
end

fn pad_code(n: Int, a: Int) -> Code
  CB(lebytes(0, sub(align_up(n, a), n)))
end

# import directory, lookup tables, address tables (the imp:sym labels), hint/name entries, dll names
fn import_blob(dlls: List[Dll]) -> Code
  let n = list_len(dlls)
  let ks = list_range(0, n)
  let desc = list_fold(ks, CNil, fn(acc, k)
    let d = show(k)
    CCat(acc, cat([CFix(8, 0, str_cat("ilt:", d)), CB(lebytes(0, 8)), CFix(8, 0, str_cat("dll:", d)), CFix(8, 0, str_cat("iat:", d))]))
  end)
  let tables = list_fold(ks, CNil, fn(acc, k)
    let dll = unwrap_or(list_get(dlls, k), Dll { name: "", syms: [] })
    let d = show(k)
    let ilt = cat(list_concat(list_concat([CLab(str_cat("ilt:", d))], list_map(dll.syms, fn(s) CFix(9, 0, str_cat("hint:", s)) end)), [CB(lebytes(0, 8))]))
    let iat = cat(list_concat(list_concat([CLab(str_cat("iat:", d))], list_map(dll.syms, fn(s) CCat(CLab(imp_label(s)), CFix(9, 0, str_cat("hint:", s))) end)), [CB(lebytes(0, 8))]))
    CCat(acc, CCat(ilt, iat))
  end)
  let names = list_fold(ks, CNil, fn(acc, k)
    let dll = unwrap_or(list_get(dlls, k), Dll { name: "", syms: [] })
    let hints = list_fold(dll.syms, CNil, fn(a2, s)
      let len = add(3, str_len(s))
      CCat(a2, cat([CLab(str_cat("hint:", s)), CB([0, 0]), CS(s), CB(lebytes(0, sub(align_up(len, 2), sub(len, 1))))]))
    end)
    CCat(CCat(acc, hints), cat([CLab(str_cat("dll:", show(k))), CS(dll.name), CB(lebytes(0, sub(align_up(add(str_len(dll.name), 1), 2), str_len(dll.name))))]))
  end)
  let desc_size = mul(20, add(n, 1))
  cat([CLab("idata"), desc, CB(lebytes(0, 20)), pad_code(desc_size, 8), tables, names, CLab("idata_end")])
end

fn write_pe(o: Out) -> Image
  let dlls = group_dlls(o.imports)
  let idata = assemble(Target { name: "windows-x64", os: "windows", arch: "x64" }, import_blob(dlls))
  let l = link_regions(o.text, list_push(o.data, idata), add(pe_base, 4096), 4096, pe_base)
  let text_rva = 4096
  let data_rva = sub(l.data_addr, pe_base)
  let text_raw = align_up(str_len(l.text), pe_file_align)
  let data_raw = align_up(str_len(l.data), pe_file_align)
  let headers = 512
  let image_size = align_up(add(data_rva, str_len(l.data)), 4096)
  let rva = fn(name) sub(sym_addr(l, name), pe_base) end
  let iat_start = rva("iat:0")
  let iat_size = sub(rva("idata_end"), iat_start)
  let dos = list_concat(list_concat([77, 90], lebytes(0, 58)), lebytes(64, 4))
  let coff = le_all([[80, 69, 0, 0], lebytes(0x8664, 2), lebytes(2, 2), lebytes(0, 12), lebytes(0xF0, 2), lebytes(0x23, 2)])
  let dirs = le_all([lebytes(0, 8), lebytes(rva("idata"), 4), lebytes(mul(20, add(list_len(dlls), 1)), 4), lebytes(0, 80),
    lebytes(iat_start, 4), lebytes(iat_size, 4), lebytes(0, 24)])
  let opt = le_all([lebytes(0x20B, 2), [1, 0], lebytes(text_raw, 4), lebytes(data_raw, 4), lebytes(0, 4), lebytes(rva("_start"), 4), lebytes(text_rva, 4),
    lebytes(pe_base, 8), lebytes(4096, 4), lebytes(pe_file_align, 4), lebytes(6, 2), lebytes(0, 2), lebytes(0, 4), lebytes(6, 2), lebytes(0, 2), lebytes(0, 4),
    lebytes(image_size, 4), lebytes(headers, 4), lebytes(0, 4), lebytes(3, 2), lebytes(0x8100, 2),
    lebytes(268435456, 8), lebytes(268435456, 8), lebytes(1048576, 8), lebytes(4096, 8), lebytes(0, 4), lebytes(16, 4), dirs])
  let sec_text = le_all([[46, 116, 101, 120, 116, 0, 0, 0], lebytes(str_len(l.text), 4), lebytes(text_rva, 4), lebytes(text_raw, 4), lebytes(headers, 4),
    lebytes(0, 12), lebytes(0x60000020, 4)])
  let sec_data = le_all([[46, 100, 97, 116, 97, 0, 0, 0], lebytes(str_len(l.data), 4), lebytes(data_rva, 4), lebytes(data_raw, 4), lebytes(add(headers, text_raw), 4),
    lebytes(0, 12), lebytes(0xC0000040, 4)])
  let head = str_from_bytes(le_all([dos, coff, opt, sec_text, sec_data]))
  let bytes = join_all(strs_from([head, zeros_str(sub(headers, str_len(head))), l.text, zeros_str(sub(text_raw, str_len(l.text))), l.data, zeros_str(sub(data_raw, str_len(l.data)))]))
  Image { bytes: bytes, missing: l.missing }
end
