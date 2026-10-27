# Code ropes, assembling (IR lowering + label resolution) and linking text and data regions.

type Target = { name: String, os: String, arch: String } end

let targets = [
  Target { name: "linux-x64", os: "linux", arch: "x64" },
  Target { name: "windows-x64", os: "windows", arch: "x64" },
  Target { name: "macos-x64", os: "macos", arch: "x64" },
  Target { name: "macos-arm64", os: "macos", arch: "arm64" }
]

fn find_target(name: String) -> Option[Target]
  match list_filter(targets, fn(t) eq(t.name, name) end)
    case [t, .._] -> Some(t)
    case [] -> None
  end
end

# ---------- code rope ----------
# CB raw bytes · CS raw string · CLab label · CRel x86 rel32 to label · CA64 absolute address ·
# CFix(kind, word, label) patched 4/8-byte field (arm64 branches/pages, PE RVAs) · CI IR instructions.
# Fixup kinds: 0 rel32, 2 abs64, 3 b26, 4 bc19, 5 adrp, 6 add-lo12, 7 ldst-lo12 (scaled by 8), 8 rva32, 9 rva64.
# Labels starting with "." are local to one blob.

type Code = CNil | CB(List[Int]) | CS(String) | CLab(String) | CRel(String) | CA64(String) | CFix(Int, Int, String) | CI(List[Ins]) | CCat(Code, Code) end
type Items = INil | ICons(Code, Items) end

fn cat(parts: List[Code]) -> Code
  list_fold(parts, CNil, fn(acc, c) CCat(acc, c) end)
end

fn lebytes(n: Int, k: Int) -> List[Int]
  le_acc(n, k, [])
end

fn le_acc(n: Int, k: Int, acc: List[Int]) -> List[Int]
  if eq(k, 0) then acc else le_acc(div(n, 256), sub(k, 1), list_push(acc, mod(n, 256))) end
end

fn pow2(n: Int) -> Int
  bit_shl(1, n)
end

fn align_up(n: Int, a: Int) -> Int
  mul(div(add(n, sub(a, 1)), a), a)
end

# IR -> machine code for one instruction
fn lower(t: Target, i: Ins) -> Code
  if eq(t.arch, "arm64") then lower_a64(t, i) else lower_x64(t, i) end
end

fn flatten(t: Target, c: Code, acc: Items) -> Items
  match c
    case CNil -> acc
    case CCat(a, b) -> flatten(t, a, flatten(t, b, acc))
    case CI(l) -> list_fold(list_reverse(l), acc, fn(a, ins) flatten(t, lower(t, ins), a) end)
    case leaf -> ICons(leaf, acc)
  end
end

# ---------- assembling one blob ----------

type Fixup = { off: Int, kind: Int, sym: String, word: Int } end
type Sym = { name: String, off: Int } end
type Blob = { bytes: String, syms: List[Sym], fixups: List[Fixup] } end
type Strs = SNil | SCons(String, Strs) end
type Asm1 = { off: Int, locals: Map[Int], syms: List[Sym] } end
type Asm2 = { off: Int, pieces: Strs, fixups: List[Fixup] } end

fn item_size(c: Code) -> Int
  match c
    case CB(l) -> list_len(l)
    case CS(s) -> str_len(s)
    case CRel(_) -> 4
    case CA64(_) -> 8
    case CFix(k, _, _) -> if eq(k, 9) then 8 else 4 end
    case _ -> 0
  end
end

fn pass1(items: Items, a: Asm1) -> Asm1
  match items
    case INil -> a
    case ICons(CLab(l), rest) ->
      if str_starts(l, ".") then pass1(rest, { a with locals: map.set(a.locals, l, a.off) })
      else pass1(rest, { a with syms: list_push(a.syms, Sym { name: l, off: a.off }), locals: map.set(a.locals, l, a.off) }) end
    case ICons(c, rest) -> pass1(rest, { a with off: add(a.off, item_size(c)) })
  end
end

# value bytes of a fixup at absolute address p whose target is t
fn fix_bytes(kind: Int, word: Int, p: Int, t: Int, image_base: Int) -> List[Int]
  if eq(kind, 0) then lebytes(sub(t, add(p, 4)), 4)
  elif eq(kind, 2) then lebytes(t, 8)
  elif eq(kind, 3) then lebytes(add(word, mod(div(sub(t, p), 4), pow2(26))), 4)
  elif eq(kind, 4) then lebytes(add(word, mul(mod(div(sub(t, p), 4), pow2(19)), 32)), 4)
  elif eq(kind, 5) then
    let pd = sub(div(t, 4096), div(p, 4096))
    lebytes(add(add(word, mul(mod(pd, 4), pow2(29))), mul(mod(div(pd, 4), pow2(19)), 32)), 4)
  elif eq(kind, 6) then lebytes(add(word, mul(mod(t, 4096), 1024)), 4)
  elif eq(kind, 7) then lebytes(add(word, mul(div(mod(t, 4096), 8), 1024)), 4)
  elif eq(kind, 8) then lebytes(sub(t, image_base), 4)
  else lebytes(sub(t, image_base), 8)
  end
end

let zero4 = str_from_bytes([0, 0, 0, 0])
let zero8 = str_from_bytes([0, 0, 0, 0, 0, 0, 0, 0])

fn local_kind(k: Int) -> Bool
  or(or(eq(k, 0), eq(k, 3)), eq(k, 4))
end

fn pass2(items: Items, locals: Map[Int], a: Asm2) -> Asm2
  match items
    case INil -> a
    case ICons(c, rest) ->
      let n = item_size(c)
      let next = match c
        case CB(l) -> { a with pieces: SCons(str_from_bytes(l), a.pieces) }
        case CS(s) -> { a with pieces: SCons(s, a.pieces) }
        case CRel(l) -> resolve_item(a, locals, 0, 0, l)
        case CA64(l) -> { a with pieces: SCons(zero8, a.pieces), fixups: list_push(a.fixups, Fixup { off: a.off, kind: 2, sym: l, word: 0 }) }
        case CFix(k, w, l) -> resolve_item(a, locals, k, w, l)
        case _ -> a
      end
      pass2(rest, locals, { next with off: add(a.off, n) })
  end
end

# relative fixups to labels of the same blob are resolved here; everything else is left to the linker
fn resolve_item(a: Asm2, locals: Map[Int], k: Int, w: Int, l: String) -> Asm2
  match if local_kind(k) then map.get(locals, l) else None end
    case Some(t) -> { a with pieces: SCons(str_from_bytes(fix_bytes(k, w, a.off, t, 0)), a.pieces) }
    case None ->
      let z = if eq(k, 9) then zero8 else zero4 end
      { a with pieces: SCons(z, a.pieces), fixups: list_push(a.fixups, Fixup { off: a.off, kind: k, sym: l, word: w }) }
  end
end

fn strs_reverse(s: Strs, acc: Strs) -> Strs
  match s
    case SNil -> acc
    case SCons(x, rest) -> strs_reverse(rest, SCons(x, acc))
  end
end

fn strs_pairs(s: Strs, acc: Strs) -> Strs
  match s
    case SNil -> strs_reverse(acc, SNil)
    case SCons(a, SNil) -> strs_reverse(SCons(a, acc), SNil)
    case SCons(a, SCons(b, rest)) -> strs_pairs(rest, SCons(str_cat(a, b), acc))
  end
end

# concatenates many strings in O(total * log count) by merging neighbours pairwise
fn join_all(s: Strs) -> String
  match s
    case SNil -> ""
    case SCons(a, SNil) -> a
    case _ -> join_all(strs_pairs(s, SNil))
  end
end

fn assemble(t: Target, c: Code) -> Blob
  let items = flatten(t, c, INil)
  let a1 = pass1(items, Asm1 { off: 0, locals: map.empty(), syms: [] })
  let a2 = pass2(items, a1.locals, Asm2 { off: 0, pieces: SNil, fixups: [] })
  Blob { bytes: join_all(strs_reverse(a2.pieces, SNil)), syms: a1.syms, fixups: a2.fixups }
end

# ---------- linking ----------

type Placed = { addr: Int, blob: Blob } end
type Region = { addr: Int, placed: List[Placed], syms: Map[Int] } end
type LinkOut = { text: String, data: String, text_addr: Int, data_addr: Int, syms: Map[Int], missing: List[String] } end
type Patch = { pos: Int, out: Strs, missing: List[String] } end

fn place(blobs: List[Blob], start: Int, syms: Map[Int]) -> Region
  list_fold(blobs, Region { addr: start, placed: [], syms: syms }, fn(acc, b)
    let s2 = list_fold(b.syms, acc.syms, fn(m, s) map.set(m, s.name, add(acc.addr, s.off)) end)
    Region { addr: align_up(add(acc.addr, str_len(b.bytes)), 8), placed: list_push(acc.placed, Placed { addr: acc.addr, blob: b }), syms: s2 }
  end)
end

fn patch_blob(p: Placed, syms: Map[Int], image_base: Int, st: Patch) -> Patch
  let r = list_fold(p.blob.fixups, Patch { pos: 0, out: st.out, missing: st.missing }, fn(acc, f)
    let before = SCons(str_slice(p.blob.bytes, acc.pos, f.off), acc.out)
    let size = if or(eq(f.kind, 2), eq(f.kind, 9)) then 8 else 4 end
    match map.get(syms, f.sym)
      case None -> Patch { pos: add(f.off, size), out: SCons(if eq(size, 8) then zero8 else zero4 end, before), missing: list_push(acc.missing, f.sym) }
      case Some(t) -> Patch { pos: add(f.off, size), out: SCons(str_from_bytes(fix_bytes(f.kind, f.word, add(p.addr, f.off), t, image_base)), before), missing: acc.missing }
    end
  end)
  let size = str_len(p.blob.bytes)
  let tail = SCons(str_slice(p.blob.bytes, r.pos, size), r.out)
  let pad = sub(align_up(add(p.addr, size), 8), add(p.addr, size))
  { r with out: SCons(str_repeat(str_from_bytes([0]), pad), tail) }
end

fn patch_region(r: Region, syms: Map[Int], image_base: Int) -> Patch
  list_fold(r.placed, Patch { pos: 0, out: SNil, missing: [] }, fn(acc, pl) patch_blob(pl, syms, image_base, acc) end)
end

# text at text_addr; data starts at the next seg_align boundary after the text
fn link_regions(text: List[Blob], data: List[Blob], text_addr: Int, seg_align: Int, image_base: Int) -> LinkOut
  let tr = place(text, text_addr, map.empty())
  let data_addr = align_up(tr.addr, seg_align)
  let dr = place(data, data_addr, tr.syms)
  let tp = patch_region(tr, dr.syms, image_base)
  let dp = patch_region(dr, dr.syms, image_base)
  LinkOut { text: join_all(strs_reverse(tp.out, SNil)), data: join_all(strs_reverse(dp.out, SNil)), text_addr: text_addr, data_addr: data_addr,
    syms: dr.syms, missing: list_concat(tp.missing, dp.missing) }
end

fn sym_addr(l: LinkOut, name: String) -> Int
  unwrap_or(map.get(l.syms, name), 0)
end

fn zeros_str(n: Int) -> String
  str_repeat(str_from_bytes([0]), max(0, n))
end
