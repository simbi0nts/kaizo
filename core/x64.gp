# x86-64: instruction encoders and the lowering of IR instructions to machine code.

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

fn x_op_rr(opc: Int, dst: Int, src: Int) -> List[Int]
  [rex(true, src, 0, dst), opc, modrm(3, src, dst)]
end

fn x_mov(d: Int, s: Int) -> List[Int]
  x_op_rr(137, d, s)
end

fn x_load(d: Int, base: Int, disp: Int) -> List[Int]
  list_concat([rex(true, d, 0, base), 139], mem(d, base, disp))
end

fn x_store(base: Int, disp: Int, s: Int) -> List[Int]
  list_concat([rex(true, s, 0, base), 137], mem(s, base, disp))
end

fn x_lea(d: Int, base: Int, disp: Int) -> List[Int]
  list_concat([rex(true, d, 0, base), 141], mem(d, base, disp))
end

fn x_movi(r: Int, n: Int) -> List[Int]
  if and(ge(n, 0), lt(n, 2147483648)) then
    cat3(if ge(r, 8) then [65] else [] end, [add(184, mod(r, 8))], lebytes(n, 4))
  else
    list_concat([rex(true, 0, 0, r), add(184, mod(r, 8))], lebytes(n, 8))
  end
end

fn x_alu_imm(ext: Int, r: Int, n: Int) -> List[Int]
  list_concat([rex(true, 0, 0, r), 129, modrm(3, ext, r)], lebytes(n, 4))
end

fn x_shift(ext: Int, r: Int, n: Int) -> List[Int]
  [rex(true, 0, 0, r), 193, modrm(3, ext, r), n]
end

fn x_push(r: Int) -> List[Int]
  if ge(r, 8) then [65, add(80, mod(r, 8))] else [add(80, r)] end
end

fn x_pop(r: Int) -> List[Int]
  if ge(r, 8) then [65, add(88, mod(r, 8))] else [add(88, r)] end
end

fn x_ret(n: Int) -> List[Int]
  if eq(n, 0) then [195] else list_concat([194], lebytes(n, 2)) end
end

fn x_mem_op(pre_op: List[Int], ext: Int, base: Int, disp: Int) -> List[Int]
  let pre = if ge(base, 8) then [65] else [] end
  cat3(pre, pre_op, mem(ext, base, disp))
end

# rip-relative operand: bytes before the disp32, then the rel32 to the label
fn x_rip(prefix: List[Int], l: String) -> Code
  CCat(CB(prefix), CRel(l))
end

# windows: rcx rdx r8 r9 (+ stack, 32-byte shadow) · others (SysV): rdi rsi rdx rcx r8 r9
fn abi_regs(t: Target) -> List[Int]
  if eq(t.os, "windows") then [rcx, rdx, r8, r9] else [rdi, rsi, rdx, rcx, r8, r9] end
end

fn imp_label(sym: String) -> String
  str_cat("imp:", sym)
end

# C call with n arguments on our stack (last on top); our stack pointer is restored afterwards
fn x_ccall(t: Target, sym: String, n: Int, ret32: Bool) -> Code
  let regs = abi_regs(t)
  let nreg = min(n, list_len(regs))
  let loads = list_fold(list_range(0, nreg), [], fn(acc, i) list_concat(acc, x_load(unwrap_or(list_get(regs, i), rax), rbx, mul(8, sub(sub(n, 1), i)))) end)
  let save = x_mov(rbx, rsp)
  let after = list_concat(x_lea(rsp, rbx, mul(8, n)), if ret32 then [72, 99, 192] else [] end)
  if eq(t.os, "windows") then
    let extra = max(0, sub(n, 4))
    let frame = list_concat(list_concat(x_mov(rax, rsp), x_alu_imm(5, rax, add(32, mul(8, extra)))), x_alu_imm(4, rax, -16))
    let stack_args = list_fold(list_range(4, max(4, n)), [], fn(acc, i)
      list_concat(acc, list_concat(x_load(r10, rbx, mul(8, sub(sub(n, 1), i))), x_store(rax, add(32, mul(8, sub(i, 4))), r10)))
    end)
    cat([CB(cat3(save, frame, list_concat(stack_args, list_concat(loads, x_mov(rsp, rax))))), x_rip([255, 21], imp_label(sym)), CB(after)])
  else
    cat([CB(cat3(save, loads, list_concat(x_alu_imm(4, rsp, -16), x_movi(rax, 0)))), x_rip([255, 21], imp_label(sym)), CB(after)])
  end
end

# C call with the arguments already in the ABI registers
fn x_craw(t: Target, sym: String) -> Code
  let shadow = if eq(t.os, "windows") then x_alu_imm(5, rsp, 32) else [] end
  cat([CB(cat3(x_mov(rbx, rsp), x_alu_imm(4, rsp, -16), shadow)), x_rip([255, 21], imp_label(sym)), CB(x_mov(rsp, rbx))])
end

fn x_tail(n: Int, m: Int) -> List[Int]
  let base = sub(add(16, mul(8, m)), mul(8, n))
  let moves = list_fold(list_reverse(list_range(0, n)), [], fn(acc, j)
    list_concat(acc, list_concat(x_load(rax, rsp, mul(8, j)), x_store(rbp, add(base, mul(8, j)), rax)))
  end)
  cat3(list_concat(x_load(rcx, rbp, 8), x_load(rdx, rbp, 0)), moves,
    cat3(x_lea(rsp, rbp, sub(base, 8)), x_store(rsp, 0, rcx), x_mov(rbp, rdx)))
end

fn lower_x64(t: Target, i: Ins) -> Code
  match i
    case IMovI(r, n) -> CB(x_movi(r, n))
    case IMov(d, s) -> CB(x_mov(d, s))
    case ILd(d, b, o) -> CB(x_load(d, b, o))
    case ISt(b, o, s) -> CB(x_store(b, o, s))
    case ILdB(d, b, o) -> CB(list_concat([rex(true, d, 0, b), 15, 182], mem(d, b, o)))
    case IStB(b, o, s) -> CB(list_concat([rex(false, s, 0, b), 136], mem(s, b, o)))
    case ILea(d, b, o) -> CB(x_lea(d, b, o))
    case IAlu(op, d, s) -> CB(x_op_rr(op, d, s))
    case IAluI(op, r, n) -> CB(x_alu_imm(op, r, n))
    case IShI(op, r, n) -> CB(x_shift(op, r, n))
    case IShCl(op, r) -> CB([rex(true, 0, 0, r), 211, modrm(3, op, r)])
    case IMul(d, s) -> CB([rex(true, d, 0, s), 15, 175, modrm(3, d, s)])
    case IDiv -> CB([72, 153, rex(true, 0, 0, r8), 247, modrm(3, 7, r8)])
    case IPush(r) -> CB(x_push(r))
    case IPop(r) -> CB(x_pop(r))
    case ITst1(r) -> CB([246, modrm(3, 0, r), 1])
    case ICmpBM(b, o, imm) -> CB(list_concat(x_mem_op([128], 7, b, o), [imm]))
    case ICmpM(b, o, imm) -> CB(cat3([rex(true, 0, 0, b), 129], mem(7, b, o), lebytes(imm, 4)))
    case ICallM(b, o) -> CB(x_mem_op([255], 2, b, o))
    case IJmpM(b, o) -> CB(x_mem_op([255], 4, b, o))
    case ISys -> CB([15, 5])
    case ICopyB -> CB([243, 164])
    case ICopyQ -> CB([243, 72, 165])
    case IEnter -> CB(list_concat(x_push(rbp), x_mov(rbp, rsp)))
    case ILeave(n) -> CB(cat3(x_mov(rsp, rbp), x_pop(rbp), x_ret(n)))
    case ITail(n, m) -> CB(x_tail(n, m))
    case IAddr(r, l) -> x_rip([rex(true, r, 0, 0), 141, modrm(0, r, 5)], l)
    case ILdG(r, l) -> x_rip([rex(true, r, 0, 0), 139, modrm(0, r, 5)], l)
    case IStG(l, r) -> x_rip([rex(true, r, 0, 0), 137, modrm(0, r, 5)], l)
    case ICall(l) -> x_rip([232], l)
    case IJmp(l) -> x_rip([233], l)
    case IJcc(c, l) -> x_rip([15, add(128, c)], l)
    case ICCall(sym, n, r32) -> x_ccall(t, sym, n, r32)
    case ICRaw(sym) -> x_craw(t, sym)
    case ISxtw -> CB([72, 99, 192])
  end
end
