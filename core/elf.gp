# ELF64 executable for Linux x86-64: headers + code (R-X) + data (RW-), entry at _start.

let elf_base = 4194304

type Image = { bytes: String, missing: List[String] } end

fn le_all(parts: List[List[Int]]) -> List[Int]
  list_fold(parts, [], fn(acc, p) list_concat(acc, p) end)
end

fn write_elf(o: Out) -> Image
  let l = link_regions(o.text, o.data, add(elf_base, 4096), 4096, 0)
  let text_end = sub(add(l.text_addr, str_len(l.text)), elf_base)
  let data_off = sub(l.data_addr, elf_base)
  let ident = [127, 69, 76, 70, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  let eh = le_all([ident, lebytes(2, 2), lebytes(62, 2), lebytes(1, 4), lebytes(sym_addr(l, "_start"), 8), lebytes(64, 8), lebytes(0, 8),
    lebytes(0, 4), lebytes(64, 2), lebytes(56, 2), lebytes(2, 2), lebytes(64, 2), lebytes(0, 2), lebytes(0, 2)])
  let ph_text = le_all([lebytes(1, 4), lebytes(5, 4), lebytes(0, 8), lebytes(elf_base, 8), lebytes(elf_base, 8), lebytes(text_end, 8), lebytes(text_end, 8), lebytes(4096, 8)])
  let ph_data = le_all([lebytes(1, 4), lebytes(6, 4), lebytes(data_off, 8), lebytes(l.data_addr, 8), lebytes(l.data_addr, 8),
    lebytes(str_len(l.data), 8), lebytes(str_len(l.data), 8), lebytes(4096, 8)])
  let head = str_from_bytes(le_all([eh, ph_text, ph_data]))
  let bytes = join_all(strs_from([head, zeros_str(sub(4096, str_len(head))), l.text, zeros_str(sub(data_off, text_end)), l.data]))
  Image { bytes: bytes, missing: l.missing }
end

fn strs_from(l: List[String]) -> Strs
  list_fold(list_reverse(l), SNil, fn(acc, s) SCons(s, acc) end)
end
