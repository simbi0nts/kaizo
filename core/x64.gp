# x86-64 machine code: instruction encoders (byte lists), a code rope, and the assembler/linker
# that turns ropes into one static ELF executable. No external assembler or linker is used.

# ---------- registers ----------
let rax = 0
let rcx = 1
let rdx = 2
let rbx = 3
let rsp = 4
let rbp = 5
let rsi = 6
let rdi = 7
let r8 = 8
let r9 = 9
let r10 = 10
let r14 = 14
let r15 = 15

# condition codes
let cc_e = 4
let cc_ne = 5
let cc_l = 12
let cc_ge = 13
let cc_le = 14
let cc_g = 15
let cc_s = 8
let cc_ns = 9

# ---------- encoding helpers ----------

fn lebytes(n: Int, k: Int) -> List[Int]
  le_acc(n, k, [])
end

fn le_acc(n: Int, k: Int, acc: List[Int]) -> List[Int]
  if eq(k, 0) then acc else le_acc(div(n, 256), sub(k, 1), list_push(acc, mod(n, 256))) end
end

fn bit(c: Bool, v: Int) -> Int
  if c then v else 0 end
end

fn rex(w: Bool, r: Int, x: Int, b: Int) -> Int
  add(add(add(add(64, bit(w, 8)), bit(ge(r, 8), 4)), bit(ge(x, 8), 2)), bit(ge(b, 8), 1))
end

fn modrm(md: Int, reg: Int, rm: Int) -> Int
  add(add(mul(md, 64), mul(mod(reg, 8), 8)), mod(rm, 8))
end

# [base + disp32] operand (always the disp32 form; SIB when base is rsp/r12)
fn mem(reg: Int, base: Int, disp: Int) -> List[Int]
  let sib = if eq(mod(base, 8), 4) then [36] else [] end
  list_concat(list_concat([modrm(2, reg, base)], sib), lebytes(disp, 4))
end

fn cat3(a: List[Int], b: List[Int], c: List[Int]) -> List[Int]
  list_concat(list_concat(a, b), c)
end

# op r/m64(dst), r64(src): 0x01 add, 0x29 sub, 0x39 cmp, 0x89 mov, 0x21 and, 0x09 or, 0x31 xor, 0x85 test
fn op_rr(opc: Int, dst: Int, src: Int) -> List[Int]
  [rex(true, src, 0, dst), opc, modrm(3, src, dst)]
end

fn mov_rr(dst: Int, src: Int) -> List[Int]
  op_rr(137, dst, src)
end

fn ldm(dst: Int, base: Int, disp: Int) -> List[Int]
  list_concat([rex(true, dst, 0, base), 139], mem(dst, base, disp))
end

fn store(base: Int, disp: Int, src: Int) -> List[Int]
  list_concat([rex(true, src, 0, base), 137], mem(src, base, disp))
end

fn lea(dst: Int, base: Int, disp: Int) -> List[Int]
  list_concat([rex(true, dst, 0, base), 141], mem(dst, base, disp))
end

fn mov_imm64(r: Int, n: Int) -> List[Int]
  list_concat([rex(true, 0, 0, r), add(184, mod(r, 8))], lebytes(n, 8))
end

fn mov_imm32(r: Int, n: Int) -> List[Int]
  let pre = if ge(r, 8) then [65] else [] end
  cat3(pre, [add(184, mod(r, 8))], lebytes(n, 4))
end

# ext: 0 add, 1 or, 4 and, 5 sub, 7 cmp
fn alu_imm(ext: Int, r: Int, n: Int) -> List[Int]
  list_concat([rex(true, 0, 0, r), 129, modrm(3, ext, r)], lebytes(n, 4))
end

# ext: 4 shl, 5 shr, 7 sar
fn shift(ext: Int, r: Int, n: Int) -> List[Int]
  [rex(true, 0, 0, r), 193, modrm(3, ext, r), n]
end

fn push_r(r: Int) -> List[Int]
  if ge(r, 8) then [65, add(80, mod(r, 8))] else [add(80, r)] end
end

fn pop_r(r: Int) -> List[Int]
  if ge(r, 8) then [65, add(88, mod(r, 8))] else [add(88, r)] end
end

fn imul(dst: Int, src: Int) -> List[Int]
  [rex(true, dst, 0, src), 15, 175, modrm(3, dst, src)]
end

fn idiv(r: Int) -> List[Int]
  [rex(true, 0, 0, r), 247, modrm(3, 7, r)]
end

let cqo = [72, 153]
let syscall_op = [15, 5]
let rep_movsb = [243, 164]
let rep_movsq = [243, 72, 165]

fn ret_n(n: Int) -> List[Int]
  if eq(n, 0) then [195] else list_concat([194], lebytes(n, 2)) end
end

# test low byte of rax/rcx/rdx/rbx with an imm8
fn test_low(r: Int, imm: Int) -> List[Int]
  [246, modrm(3, 0, r), imm]
end

fn cmp_byte_mem(base: Int, disp: Int, imm: Int) -> List[Int]
  let pre = if ge(base, 8) then [65] else [] end
  cat3(pre, list_concat([128], mem(7, base, disp)), [imm])
end

fn cmp_mem_imm(base: Int, disp: Int, n: Int) -> List[Int]
  cat3([rex(true, 0, 0, base), 129], mem(7, base, disp), lebytes(n, 4))
end

fn movzx_byte(dst: Int, base: Int, disp: Int) -> List[Int]
  list_concat([rex(true, dst, 0, base), 15, 182], mem(dst, base, disp))
end

# store the low byte of src (rax/rcx/rdx/rbx only)
fn store_byte(base: Int, disp: Int, src: Int) -> List[Int]
  list_concat([rex(false, src, 0, base), 136], mem(src, base, disp))
end

fn call_mem(base: Int, disp: Int) -> List[Int]
  let pre = if ge(base, 8) then [65] else [] end
  cat3(pre, [255], mem(2, base, disp))
end

fn jmp_mem(base: Int, disp: Int) -> List[Int]
  let pre = if ge(base, 8) then [65] else [] end
  cat3(pre, [255], mem(4, base, disp))
end

# ---------- code rope ----------
# CB: raw bytes · CS: raw string bytes · CLab: label here · CRel: rel32 to label ·
# CA32 / CA64: absolute address of label (4 / 8 bytes). Labels starting with "." are local.

type Code = CNil | CB(List[Int]) | CS(String) | CLab(String) | CRel(String) | CA32(String) | CA64(String) | CCat(Code, Code) end
type Items = INil | ICons(Code, Items) end

fn cat(parts: List[Code]) -> Code
  list_fold(parts, CNil, fn(acc, c) CCat(acc, c) end)
end

fn jmp(l: String) -> Code
  CCat(CB([233]), CRel(l))
end

fn jcc(c: Int, l: String) -> Code
  CCat(CB([15, add(128, c)]), CRel(l))
end

fn call_l(l: String) -> Code
  CCat(CB([232]), CRel(l))
end

# mov r32, imm32 = absolute address of label (fits: image is below 2 GiB)
fn mov_addr(r: Int, l: String) -> Code
  let pre = if ge(r, 8) then [65] else [] end
  CCat(CB(list_concat(pre, [add(184, mod(r, 8))])), CA32(l))
end

# mov rax, [abs32]  /  mov [abs32], r
fn load_abs(r: Int, l: String) -> Code
  CCat(CB([rex(true, r, 0, 0), 139, modrm(0, r, 4), 37]), CA32(l))
end

fn store_abs(l: String, r: Int) -> Code
  CCat(CB([rex(true, r, 0, 0), 137, modrm(0, r, 4), 37]), CA32(l))
end

fn flatten(c: Code, acc: Items) -> Items
  match c
    case CNil -> acc
    case CCat(a, b) -> flatten(a, flatten(b, acc))
    case leaf -> ICons(leaf, acc)
  end
end

# ---------- assembling one blob ----------

type Fixup = { off: Int, kind: Int, sym: String } end
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
    case CA32(_) -> 4
    case CA64(_) -> 8
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

let zero4 = str_from_bytes([0, 0, 0, 0])
let zero8 = str_from_bytes([0, 0, 0, 0, 0, 0, 0, 0])

fn pass2(items: Items, locals: Map[Int], a: Asm2) -> Asm2
  match items
    case INil -> a
    case ICons(c, rest) ->
      let n = item_size(c)
      let next = match c
        case CB(l) -> { a with pieces: SCons(str_from_bytes(l), a.pieces) }
        case CS(s) -> { a with pieces: SCons(s, a.pieces) }
        case CRel(l) ->
          match map.get(locals, l)
            case Some(t) -> { a with pieces: SCons(str_from_bytes(lebytes(sub(t, add(a.off, 4)), 4)), a.pieces) }
            case None -> { a with pieces: SCons(zero4, a.pieces), fixups: list_push(a.fixups, Fixup { off: a.off, kind: 0, sym: l }) }
          end
        case CA32(l) -> { a with pieces: SCons(zero4, a.pieces), fixups: list_push(a.fixups, Fixup { off: a.off, kind: 1, sym: l }) }
        case CA64(l) -> { a with pieces: SCons(zero8, a.pieces), fixups: list_push(a.fixups, Fixup { off: a.off, kind: 2, sym: l }) }
        case _ -> a
      end
      pass2(rest, locals, { next with off: add(a.off, n) })
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

fn assemble(c: Code) -> Blob
  let items = flatten(c, INil)
  let a1 = pass1(items, Asm1 { off: 0, locals: map.empty(), syms: [] })
  let a2 = pass2(items, a1.locals, Asm2 { off: 0, pieces: SNil, fixups: [] })
  Blob { bytes: join_all(strs_reverse(a2.pieces, SNil)), syms: a1.syms, fixups: a2.fixups }
end

# ---------- linking into an ELF executable ----------

let base_addr = 4194304
let header_size = 120

type Placed = { addr: Int, blob: Blob } end
type Layout = { addr: Int, placed: List[Placed], syms: Map[Int] } end

fn pad_to8(n: Int) -> Int
  mul(div(add(n, 7), 8), 8)
end

fn layout(blobs: List[Blob]) -> Layout
  list_fold(blobs, Layout { addr: add(base_addr, header_size), placed: [], syms: map.empty() }, fn(acc, b)
    let syms = list_fold(b.syms, acc.syms, fn(m, s) map.set(m, s.name, add(acc.addr, s.off)) end)
    Layout { addr: pad_to8(add(acc.addr, str_len(b.bytes))), placed: list_push(acc.placed, Placed { addr: acc.addr, blob: b }), syms: syms }
  end)
end

type Patch = { pos: Int, out: Strs, missing: List[String] } end

fn patch_blob(p: Placed, syms: Map[Int], st: Patch) -> Patch
  let r = list_fold(p.blob.fixups, Patch { pos: 0, out: st.out, missing: st.missing }, fn(acc, f)
    let before = SCons(str_slice(p.blob.bytes, acc.pos, f.off), acc.out)
    match map.get(syms, f.sym)
      case None -> Patch { pos: add(f.off, item_size_kind(f.kind)), out: SCons(if eq(f.kind, 2) then zero8 else zero4 end, before), missing: list_push(acc.missing, f.sym) }
      case Some(t) ->
        let v = if eq(f.kind, 0) then lebytes(sub(t, add(add(p.addr, f.off), 4)), 4) elif eq(f.kind, 1) then lebytes(t, 4) else lebytes(t, 8) end
        Patch { pos: add(f.off, list_len(v)), out: SCons(str_from_bytes(v), before), missing: acc.missing }
    end
  end)
  let size = str_len(p.blob.bytes)
  let tail = SCons(str_slice(p.blob.bytes, r.pos, size), r.out)
  let pad = sub(pad_to8(add(p.addr, size)), add(p.addr, size))
  { r with out: SCons(str_repeat(str_from_bytes([0]), pad), tail) }
end

fn item_size_kind(k: Int) -> Int
  if eq(k, 2) then 8 else 4 end
end

fn elf_header(entry: Int, total: Int) -> String
  let ident = [127, 69, 76, 70, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  let eh = list_concat(ident, list_concat(list_concat(list_concat(lebytes(2, 2), lebytes(62, 2)), list_concat(lebytes(1, 4), lebytes(entry, 8))),
    list_concat(list_concat(lebytes(64, 8), lebytes(0, 8)), list_concat(list_concat(lebytes(0, 4), lebytes(64, 2)), list_concat(list_concat(lebytes(56, 2), lebytes(1, 2)), list_concat(lebytes(64, 2), list_concat(lebytes(0, 2), lebytes(0, 2))))))))
  let ph = list_concat(list_concat(list_concat(lebytes(1, 4), lebytes(7, 4)), list_concat(lebytes(0, 8), lebytes(base_addr, 8))),
    list_concat(list_concat(lebytes(base_addr, 8), lebytes(total, 8)), list_concat(lebytes(total, 8), lebytes(4096, 8))))
  str_from_bytes(list_concat(eh, ph))
end

type Image = { bytes: String, missing: List[String] } end

fn link_image(blobs: List[Blob], entry: String) -> Image
  let lay = layout(blobs)
  let p = list_fold(lay.placed, Patch { pos: 0, out: SNil, missing: [] }, fn(acc, pl) patch_blob(pl, lay.syms, acc) end)
  let total = sub(lay.addr, base_addr)
  let entry_addr = unwrap_or(map.get(lay.syms, entry), 0)
  let body = join_all(strs_reverse(p.out, SNil))
  Image { bytes: str_cat(elf_header(entry_addr, total), body), missing: p.missing }
end
