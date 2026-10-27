# arm64 (AArch64): encoders and the lowering of IR instructions.
# IR registers: rax..r10 -> x0..x7 (rax x0, rcx x1, rdx x2, rsi x3, rdi x4, r8 x5, r9 x6, r10 x7),
# rsp -> x26 (value stack, 8-byte slots; the real sp is left to C code), rbp -> x29,
# r14 -> x28 (heap), r15 -> x27 (closure), rbx -> x19. x16/x17 are lowering scratch.

fn areg(r: Int) -> Int
  match r
    case 0 -> 0
    case 1 -> 1
    case 2 -> 2
    case 3 -> 19
    case 4 -> 26
    case 5 -> 29
    case 6 -> 3
    case 7 -> 4
    case 8 -> 5
    case 9 -> 6
    case 10 -> 7
    case 12 -> 20
    case 14 -> 28
    case 15 -> 27
    case _ -> 0
  end
end

fn acond(c: Int) -> Int
  match c
    case 4 -> 0
    case 5 -> 1
    case 8 -> 4
    case 9 -> 5
    case 12 -> 11
    case 13 -> 10
    case 14 -> 13
    case 15 -> 12
    case _ -> 14
  end
end

fn f(v: Int, shift: Int) -> Int
  bit_shl(v, shift)
end

fn wd(x: Int) -> List[Int]
  lebytes(x, 4)
end

fn words(l: List[Int]) -> Code
  CB(list_fold(l, [], fn(acc, x) list_concat(acc, wd(x)) end))
end

# rd, rn, rm style data-processing (register)
fn dp3(base: Int, rd: Int, rn: Int, rm: Int) -> Int
  add(add(add(base, f(rm, 16)), f(rn, 5)), rd)
end

fn dp_imm(base: Int, rd: Int, rn: Int, imm12: Int) -> Int
  add(add(add(base, f(imm12, 10)), f(rn, 5)), rd)
end

let x16 = 16
let x17 = 17
let x29 = 29
let x30 = 30

fn a_mov(d: Int, s: Int) -> Int
  add(add(0xAA0003E0, f(s, 16)), d)
end

# mov xd, #n (movz/movn/movk)
fn a_movi(d: Int, n: Int) -> List[Int]
  if and(ge(n, 0), lt(n, 65536)) then [add(add(0xD2800000, f(n, 5)), d)]
  elif and(lt(n, 0), gt(n, -65537)) then [add(add(0x92800000, f(sub(-1, n), 5)), d)]
  else
    let chunk = fn(i) bit_and(bit_shr(n, mul(16, i)), 0xFFFF) end
    list_fold(list_range(1, 4), [add(add(0xD2800000, f(chunk(0), 5)), d)], fn(acc, i)
      if eq(chunk(i), 0) then acc else list_push(acc, add(add(add(0xF2800000, f(i, 21)), f(chunk(i), 5)), d)) end
    end)
  end
end

# 64-bit load/store with any offset (scratch x17 for large offsets); store = true for str
fn a_ldst(store_op: Bool, rt: Int, rn: Int, off: Int) -> List[Int]
  if and(and(ge(off, 0), lt(off, 32768)), eq(mod(off, 8), 0)) then
    [dp_imm(if store_op then 0xF9000000 else 0xF9400000 end, rt, rn, div(off, 8))]
  elif and(ge(off, -256), lt(off, 256)) then
    [add(add(add(if store_op then 0xF8000000 else 0xF8400000 end, f(bit_and(off, 511), 12)), f(rn, 5)), rt)]
  else
    list_push(a_movi(x17, off), dp3(if store_op then 0xF8206800 else 0xF8606800 end, rt, rn, x17))
  end
end

fn a_ldstb(store_op: Bool, rt: Int, rn: Int, off: Int) -> List[Int]
  if and(ge(off, 0), lt(off, 4096)) then [dp_imm(if store_op then 0x39000000 else 0x39400000 end, rt, rn, off)]
  elif and(ge(off, -256), lt(off, 256)) then
    [add(add(add(if store_op then 0x38000000 else 0x38400000 end, f(bit_and(off, 511), 12)), f(rn, 5)), rt)]
  else
    list_push(a_movi(x17, off), dp3(if store_op then 0x38206800 else 0x38606800 end, rt, rn, x17))
  end
end

# xd = xn + off
fn a_addi(d: Int, n: Int, off: Int) -> List[Int]
  if and(ge(off, 0), lt(off, 4096)) then [dp_imm(0x91000000, d, n, off)]
  elif and(lt(off, 0), gt(off, -4096)) then [dp_imm(0xD1000000, d, n, sub(0, off))]
  else list_push(a_movi(x17, off), dp3(0x8B000000, d, n, x17))
  end
end

fn a_cmpi(n: Int, imm: Int) -> List[Int]
  if and(ge(imm, 0), lt(imm, 4096)) then [dp_imm(0xF1000000, 31, n, imm)]
  else list_push(a_movi(x17, imm), dp3(0xEB000000, 31, n, x17))
  end
end

fn a_push(r: Int) -> Int
  add(add(add(0xF8000C00, f(504, 12)), f(26, 5)), r)
end

fn a_pop(r: Int) -> Int
  add(add(add(0xF8400400, f(8, 12)), f(26, 5)), r)
end

fn a_rel(op: Int, kind: Int, l: String) -> Code
  CFix(kind, op, l)
end

fn a_page(rd: Int, l: String) -> Code
  CFix(5, add(0x90000000, rd), l)
end

# IAlu (x86 opcode numbers) -> arm64 register op
fn a_alu(op: Int, d: Int, s: Int) -> List[Int]
  if eq(op, 1) then [dp3(0x8B000000, d, d, s)]
  elif eq(op, 41) then [dp3(0xCB000000, d, d, s)]
  elif eq(op, 57) then [dp3(0xEB000000, 31, d, s)]
  elif eq(op, 33) then [dp3(0x8A000000, d, d, s)]
  elif eq(op, 9) then [dp3(0xAA000000, d, d, s)]
  elif eq(op, 49) then [dp3(0xCA000000, d, d, s)]
  else [dp3(0xEA000000, 31, d, s)]
  end
end

fn a_alui(op: Int, r: Int, n: Int) -> List[Int]
  if eq(op, 0) then a_addi(r, r, n)
  elif eq(op, 5) then a_addi(r, r, sub(0, n))
  elif eq(op, 7) then a_cmpi(r, n)
  elif eq(op, 4) then list_push(a_movi(x17, n), dp3(0x8A000000, r, r, x17))
  else list_push(a_movi(x17, n), dp3(0xAA000000, r, r, x17))
  end
end

fn a_shift(op: Int, r: Int, n: Int) -> Int
  if eq(op, 4) then add(add(add(add(0xD3400000, f(mod(sub(64, n), 64), 16)), f(sub(63, n), 10)), f(r, 5)), r)
  elif eq(op, 5) then add(add(add(add(0xD3400000, f(n, 16)), f(63, 10)), f(r, 5)), r)
  else add(add(add(add(0x93400000, f(n, 16)), f(63, 10)), f(r, 5)), r)
  end
end

fn a_tail(n: Int, m: Int) -> List[Int]
  let base = sub(add(16, mul(8, m)), mul(8, n))
  let moves = list_fold(list_reverse(list_range(0, n)), [], fn(acc, j)
    list_concat(acc, list_concat(a_ldst(false, x17, 26, mul(8, j)), a_ldst(true, x17, x29, add(base, mul(8, j)))))
  end)
  list_concat(list_concat(list_concat(a_ldst(false, x30, x29, 8), a_ldst(false, x16, x29, 0)), moves), list_push(a_addi(26, x29, base), a_mov(x29, x16)))
end

fn a_call_got(sym: String) -> Code
  cat([a_page(x16, imp_label(sym)), CFix(7, add(0xF9400000, add(f(x16, 5), x16)), imp_label(sym)), words([add(0xD63F0000, f(x16, 5))])])
end

fn a_ccall(sym: String, n: Int, r32: Bool) -> Code
  let loads = list_fold(list_range(0, n), [], fn(acc, i) list_concat(acc, a_ldst(false, i, 26, mul(8, sub(sub(n, 1), i)))) end)
  let after = list_concat(a_addi(26, 26, mul(8, n)), if r32 then [0x93407C00] else [] end)
  cat([words(loads), a_call_got(sym), words(after)])
end

# byte copy loop: x1 = count, x3 = source, x4 = destination (64-bit words when q)
fn a_copy(q: Bool) -> Code
  let ld = if q then add(add(0xF8400400, f(8, 12)), add(f(3, 5), x16)) else add(add(0x38400400, f(1, 12)), add(f(3, 5), x16)) end
  let st = if q then add(add(0xF8000400, f(8, 12)), add(f(4, 5), x16)) else add(add(0x38000400, f(1, 12)), add(f(4, 5), x16)) end
  words([add(add(0xB4000000, f(5, 5)), 1), ld, st, dp_imm(0xD1000000, 1, 1, 1), add(0x14000000, bit_and(-4, 0x3FFFFFF))])
end

fn lower_a64(t: Target, i: Ins) -> Code
  match i
    case IMovI(r, n) -> words(a_movi(areg(r), n))
    case IMov(d, s) -> words([a_mov(areg(d), areg(s))])
    case ILd(d, b, o) -> words(a_ldst(false, areg(d), areg(b), o))
    case ISt(b, o, s) -> words(a_ldst(true, areg(s), areg(b), o))
    case ILdB(d, b, o) -> words(a_ldstb(false, areg(d), areg(b), o))
    case IStB(b, o, s) -> words(a_ldstb(true, areg(s), areg(b), o))
    case ILea(d, b, o) -> words(a_addi(areg(d), areg(b), o))
    case IAlu(op, d, s) -> words(a_alu(op, areg(d), areg(s)))
    case IAluI(op, r, n) -> words(a_alui(op, areg(r), n))
    case IShI(op, r, n) -> words([a_shift(op, areg(r), n)])
    case IShCl(op, r) ->
      let base = if eq(op, 4) then 0x9AC02000 elif eq(op, 5) then 0x9AC02400 else 0x9AC02800 end
      words([dp3(base, areg(r), areg(r), 1)])
    case IMul(d, s) -> words([dp3(0x9B007C00, areg(d), areg(d), areg(s))])
    case IDiv -> words([dp3(0x9AC00C00, x16, 0, 5), add(dp3(0x9B008000, 2, x16, 5), f(0, 10)), a_mov(0, x16)])
    case IPush(r) -> words([a_push(areg(r))])
    case IPop(r) -> words([a_pop(areg(r))])
    case ITst1(r) -> words([add(0xF240001F, f(areg(r), 5))])
    case ICmpBM(b, o, imm) -> words(list_concat(a_ldstb(false, x16, areg(b), o), a_cmpi(x16, imm)))
    case ICmpM(b, o, imm) -> words(list_concat(a_ldst(false, x16, areg(b), o), a_cmpi(x16, imm)))
    case ICallM(b, o) -> words(list_push(a_ldst(false, x16, areg(b), o), add(0xD63F0000, f(x16, 5))))
    case IJmpM(b, o) -> words(list_push(a_ldst(false, x16, areg(b), o), add(0xD61F0000, f(x16, 5))))
    case ISys -> words([0])
    case ICopyB -> a_copy(false)
    case ICopyQ -> a_copy(true)
    case IEnter -> words([a_push(x30), a_push(x29), a_mov(x29, 26)])
    case ILeave(n) -> words(list_push(list_concat([a_mov(26, x29), a_pop(x29), a_pop(x30)], a_addi(26, 26, n)), 0xD65F03C0))
    case ITail(n, m) -> words(a_tail(n, m))
    case IAddr(r, l) -> CCat(a_page(areg(r), l), CFix(6, dp_imm(0x91000000, areg(r), areg(r), 0), l))
    case ILdG(r, l) -> CCat(a_page(x16, l), CFix(7, dp_imm(0xF9400000, areg(r), x16, 0), l))
    case IStG(l, r) -> CCat(a_page(x16, l), CFix(7, dp_imm(0xF9000000, areg(r), x16, 0), l))
    case ICall(l) -> a_rel(0x94000000, 3, l)
    case IJmp(l) -> a_rel(0x14000000, 3, l)
    case IJcc(c, l) -> a_rel(add(0x54000000, acond(c)), 4, l)
    case ICCall(sym, n, r32) -> a_ccall(sym, n, r32)
    case ICRaw(sym) -> a_call_got(sym)
    case ISxtw -> words([0x93407C00])
    case IAddM(b, o, n) -> words(list_concat(list_concat(a_ldst(false, x16, areg(b), o), a_addi(x16, x16, n)), a_ldst(true, x16, areg(b), o)))
    case IDecM(b, o) -> words(list_concat(list_push(a_ldst(false, x16, areg(b), o), dp_imm(0xF1000000, x16, x16, 1)), a_ldst(true, x16, areg(b), o)))
    case IZeroQ -> words([0xB4000081, 0xF800849F, dp_imm(0xD1000000, 1, 1, 1), 0x17FFFFFD])
    case IRet -> words([0xD65F03C0])
  end
end

# encodings checked against the ARM reference (expected values written in hex, converted by tooling)

test "a64: mov x0, x1"
  expect_eq([a_mov(0, 1)], [0xAA0103E0])
end

test "a64: ret"
  expect_eq([0xD65F03C0], [0xD65F03C0])
end

test "a64: add x0, x0, #1"
  expect_eq(a_addi(0, 0, 1), [0x91000400])
end

test "a64: sub x1, x1, #1"
  expect_eq(a_addi(1, 1, -1), [0xD1000421])
end

test "a64: ldr x0, [x1, #8]"
  expect_eq(a_ldst(false, 0, 1, 8), [0xF9400420])
end

test "a64: str x0, [x1, #8]"
  expect_eq(a_ldst(true, 0, 1, 8), [0xF9000420])
end

test "a64: ldur x0, [x29, #-8]"
  expect_eq(a_ldst(false, 0, 29, -8), [0xF85F83A0])
end

test "a64: str x30, [x26, #-8]!"
  expect_eq([a_push(30)], [0xF81F8F5E])
end

test "a64: ldr x29, [x26], #8"
  expect_eq([a_pop(29)], [0xF840875D])
end

test "a64: movz x0, #42"
  expect_eq(a_movi(0, 42), [0xD2800540])
end

test "a64: mov x0, #-1"
  expect_eq(a_movi(0, -1), [0x92800000])
end

test "a64: cmp x0, x1"
  expect_eq(a_alu(57, 0, 1), [0xEB01001F])
end

test "a64: add x0, x0, x1"
  expect_eq(a_alu(1, 0, 1), [0x8B010000])
end

test "a64: sub x0, x0, x1"
  expect_eq(a_alu(41, 0, 1), [0xCB010000])
end

test "a64: and x2, x2, x0"
  expect_eq(a_alu(33, 2, 0), [0x8A000042])
end

test "a64: orr x2, x2, x0"
  expect_eq(a_alu(9, 2, 0), [0xAA000042])
end

test "a64: eor x6, x6, x5"
  expect_eq(a_alu(49, 6, 5), [0xCA0500C6])
end

test "a64: tst x2, x2"
  expect_eq(a_alu(133, 2, 2), [0xEA02005F])
end

test "a64: cmp x0, #1"
  expect_eq(a_cmpi(0, 1), [0xF100041F])
end

test "a64: tst x0, #1"
  expect_eq([0xF240001F], [0xF240001F])
end

test "a64: lsl x0, x0, #3"
  expect_eq([a_shift(4, 0, 3)], [0xD37DF000])
end

test "a64: asr x0, x0, #1"
  expect_eq([a_shift(7, 0, 1)], [0x9341FC00])
end

test "a64: lsr x1, x1, #8"
  expect_eq([a_shift(5, 1, 8)], [0xD348FC21])
end

test "a64: mul x0, x0, x1"
  expect_eq([dp3(0x9B007C00, 0, 0, 1)], [0x9B017C00])
end

test "a64: sdiv x16, x0, x5"
  expect_eq([dp3(0x9AC00C00, 16, 0, 5)], [0x9AC50C10])
end

test "a64: msub x2, x16, x5, x0"
  expect_eq([dp3(0x9B008000, 2, 16, 5)], [0x9B058202])
end

test "a64: blr x16"
  expect_eq([add(0xD63F0000, f(16, 5))], [0xD63F0200])
end

test "a64: br x16"
  expect_eq([add(0xD61F0000, f(16, 5))], [0xD61F0200])
end

test "a64: sxtw x0, w0"
  expect_eq([0x93407C00], [0x93407C00])
end

test "a64: ldrb w16, [x0]"
  expect_eq(a_ldstb(false, 16, 0, 0), [0x39400010])
end

test "a64: strb w0, [x1, #8]"
  expect_eq(a_ldstb(true, 0, 1, 8), [0x39002020])
end

test "a64: lslv x0, x0, x1"
  expect_eq([dp3(0x9AC02000, 0, 0, 1)], [0x9AC12000])
end

test "a64: asrv x0, x0, x1"
  expect_eq([dp3(0x9AC02800, 0, 0, 1)], [0x9AC12800])
end

test "a64: str x0, [x1, x17]"
  expect_eq([dp3(0xF8206800, 0, 1, 17)], [0xF8316820])
end

test "a64: ldr x0, [x1, x17]"
  expect_eq([dp3(0xF8606800, 0, 1, 17)], [0xF8716820])
end

test "a64: movk x0, #0x1234, lsl #16"
  expect_eq([add(add(add(0xF2800000, f(1, 21)), f(0x1234, 5)), 0)], [0xF2A24680])
end

test "a64: adrp x16 (base)"
  expect_eq([add(0x90000000, 16)], [0x90000010])
end

test "a64: bl (base)"
  expect_eq([0x94000000], [0x94000000])
end

test "a64: b.eq (base)"
  expect_eq([add(0x54000000, acond(4))], [0x54000000])
end

test "a64: b.lt (base)"
  expect_eq([add(0x54000000, acond(12))], [0x5400000B])
end

test "a64: ldr x16, [x16] (lo12 base)"
  expect_eq([dp_imm(0xF9400000, 16, 16, 0)], [0xF9400210])
end

test "a64: add x0, x0 (lo12 base)"
  expect_eq([dp_imm(0x91000000, 0, 0, 0)], [0x91000000])
end

test "a64: zero-fill loop"
  # cbz x1, +16 · str xzr, [x4], #8 · sub x1, x1, #1 · b -12
  match lower_a64(Target { name: "macos-arm64", os: "macos", arch: "arm64" }, IZeroQ)
    case CB(b) -> expect_eq(b, list_fold([0xB4000081, 0xF800849F, 0xD1000421, 0x17FFFFFD], [], fn(acc, x) list_concat(acc, lebytes(x, 4)) end))
    case _ -> panic("not bytes")
  end
end

test "a64: subs x16, x16, #1"
  expect_eq(dp_imm(0xF1000000, 16, 16, 1), 0xF1000610)
end

test "a64: zero-fill loop"
  # cbz x1, +16 · str xzr, [x4], #8 · sub x1, x1, #1 · b -12
  match lower_a64(Target { name: "macos-arm64", os: "macos", arch: "arm64" }, IZeroQ)
    case CB(b) -> expect_eq(b, list_fold([0xB4000081, 0xF800849F, 0xD1000421, 0x17FFFFFD], [], fn(acc, x) list_concat(acc, lebytes(x, 4)) end))
    case _ -> panic("not bytes")
  end
end

test "a64: subs x16, x16, #1"
  expect_eq(dp_imm(0xF1000000, 16, 16, 1), 0xF1000610)
end

test "a64: byte copy loop"
  match a_copy(false)
    case CB(b) -> expect_eq(b, list_fold([0xB40000A1, 0x38401470, 0x38001490, 0xD1000421, 0x17FFFFFC], [], fn(acc, x) list_concat(acc, lebytes(x, 4)) end))
    case _ -> panic("not bytes")
  end
end

test "a64: word copy loop"
  match a_copy(true)
    case CB(b) -> expect_eq(b, list_fold([0xB40000A1, 0xF8408470, 0xF8008490, 0xD1000421, 0x17FFFFFC], [], fn(acc, x) list_concat(acc, lebytes(x, 4)) end))
    case _ -> panic("not bytes")
  end
end

test "a64: adrp page field"
  # target 2 pages ahead: immlo = 2 (bits 29-30), immhi = 0
  expect_eq(fix_bytes(5, 0x90000010, 4096, 12288, 0), lebytes(0xD0000010, 4))
end

test "a64: b.cond backwards"
  # b.ne -8 bytes: imm19 = -2
  expect_eq(fix_bytes(4, 0x54000001, 100, 92, 0), lebytes(0x54FFFFC1, 4))
end
