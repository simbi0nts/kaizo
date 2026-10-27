# Target-independent machine IR. Codegen emits these; x64.gp / a64.gp lower them to bytes.
# Registers are named after x86-64 and mapped by each lowering (arm64: rax..r10 -> x0..x7,
# rsp -> x26 value stack, rbp -> x29, r14 -> x28 heap, r15 -> x27 closure, rbx -> x19).

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

# condition codes (x86 numbering)
let cc_e = 4
let cc_ne = 5
let cc_s = 8
let cc_ns = 9
let cc_l = 12
let cc_ge = 13
let cc_le = 14
let cc_g = 15

# IAlu ops (x86 opcode numbers): 1 add, 41 sub, 57 cmp, 33 and, 9 or, 49 xor, 133 test
# IAluI ops: 0 add, 1 or, 4 and, 5 sub, 7 cmp · IShI/IShCl ops: 4 shl, 5 shr, 7 sar
type Ins =
  IMovI(Int, Int) | IMov(Int, Int) | ILd(Int, Int, Int) | ISt(Int, Int, Int) | ILdB(Int, Int, Int) | IStB(Int, Int, Int)
  | ILea(Int, Int, Int) | IAlu(Int, Int, Int) | IAluI(Int, Int, Int) | IShI(Int, Int, Int) | IShCl(Int, Int) | IMul(Int, Int)
  | IDiv | IPush(Int) | IPop(Int) | ITst1(Int) | ICmpBM(Int, Int, Int) | ICmpM(Int, Int, Int)
  | ICallM(Int, Int) | IJmpM(Int, Int) | ISys | ICopyB | ICopyQ | IEnter | ILeave(Int) | ITail(Int, Int)
  | IAddr(Int, String) | ILdG(Int, String) | IStG(String, Int) | ICall(String) | IJmp(String) | IJcc(Int, String)
  | ICCall(String, Int, Bool) | ICRaw(String) | ISxtw
end

# ---------- helpers with the names codegen uses (each returns a list of IR instructions) ----------

fn mov_rr(d: Int, s: Int) -> List[Ins]
  [IMov(d, s)]
end

fn ldm(d: Int, base: Int, off: Int) -> List[Ins]
  [ILd(d, base, off)]
end

fn store(base: Int, off: Int, s: Int) -> List[Ins]
  [ISt(base, off, s)]
end

fn lea(d: Int, base: Int, off: Int) -> List[Ins]
  [ILea(d, base, off)]
end

fn mov_imm64(r: Int, n: Int) -> List[Ins]
  [IMovI(r, n)]
end

fn mov_imm32(r: Int, n: Int) -> List[Ins]
  [IMovI(r, n)]
end

fn alu_imm(op: Int, r: Int, n: Int) -> List[Ins]
  [IAluI(op, r, n)]
end

fn shift(op: Int, r: Int, n: Int) -> List[Ins]
  [IShI(op, r, n)]
end

fn shift_cl(op: Int, r: Int) -> List[Ins]
  [IShCl(op, r)]
end

fn push_r(r: Int) -> List[Ins]
  [IPush(r)]
end

fn pop_r(r: Int) -> List[Ins]
  [IPop(r)]
end

fn imul(d: Int, s: Int) -> List[Ins]
  [IMul(d, s)]
end

fn op_rr(op: Int, d: Int, s: Int) -> List[Ins]
  [IAlu(op, d, s)]
end

fn test_low(r: Int, imm: Int) -> List[Ins]
  [ITst1(r)]
end

fn cmp_byte_mem(base: Int, off: Int, imm: Int) -> List[Ins]
  [ICmpBM(base, off, imm)]
end

fn cmp_mem_imm(base: Int, off: Int, imm: Int) -> List[Ins]
  [ICmpM(base, off, imm)]
end

fn movzx_byte(d: Int, base: Int, off: Int) -> List[Ins]
  [ILdB(d, base, off)]
end

fn store_byte(base: Int, off: Int, s: Int) -> List[Ins]
  [IStB(base, off, s)]
end

fn call_mem(base: Int, off: Int) -> List[Ins]
  [ICallM(base, off)]
end

fn jmp_mem(base: Int, off: Int) -> List[Ins]
  [IJmpM(base, off)]
end

# rax = rax / r8 (truncating), rdx = remainder
let div_op = [IDiv]
let syscall_op = [ISys]
let rep_movsb = [ICopyB]
let rep_movsq = [ICopyQ]
