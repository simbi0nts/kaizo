#!/usr/bin/env python3
"""Sampling profiler for kaizo-built Linux x86-64 binaries (no perf needed).
usage: tools/kprof.py <binary> [args...]   (build with: kaizo build app.gp -o app --map)
Stops the program every ~1 ms with ptrace, records rip, maps it to <binary>.map, prints the top functions."""
import ctypes, os, signal, sys, time, bisect, collections
libc = ctypes.CDLL(None, use_errno=True)
libc.ptrace.restype = ctypes.c_long
libc.ptrace.argtypes = [ctypes.c_long, ctypes.c_long, ctypes.c_void_p, ctypes.c_void_p]
PTRACE_TRACEME, PTRACE_CONT, PTRACE_GETREGS = 0, 7, 12
class Regs(ctypes.Structure):
    _fields_ = [(n, ctypes.c_ulonglong) for n in "r15 r14 r13 r12 rbp rbx r11 r10 r9 r8 rax rcx rdx rsi rdi orig_rax rip cs eflags rsp ss fs_base gs_base ds es fs gs".split()]
prog = sys.argv[1:]
syms = []
for line in open(prog[0] + ".map"):
    a, n = line.split(None, 1); syms.append((int(a, 16), n.strip()))
syms.sort(); addrs = [a for a, _ in syms]
pid = os.fork()
if pid == 0:
    libc.ptrace(PTRACE_TRACEME, 0, None, None)
    devnull = os.open(os.devnull, os.O_WRONLY); os.dup2(devnull, 1)
    os.execv(prog[0], prog)
os.waitpid(pid, 0)                       # stopped at exec
libc.ptrace(PTRACE_CONT, pid, None, None)
counts = collections.Counter(); regs = Regs(); total = 0
while True:
    time.sleep(0.001)
    try: os.kill(pid, signal.SIGSTOP)
    except ProcessLookupError: break
    _, st = os.waitpid(pid, 0)
    if os.WIFEXITED(st) or os.WIFSIGNALED(st): break
    sig = os.WSTOPSIG(st)
    if libc.ptrace(PTRACE_GETREGS, pid, None, ctypes.byref(regs)) == 0:
        i = bisect.bisect_right(addrs, regs.rip) - 1
        counts[syms[i][1] if i >= 0 else hex(regs.rip)] += 1; total += 1
    libc.ptrace(PTRACE_CONT, pid, None, ctypes.c_void_p(0 if sig == signal.SIGSTOP else sig))
for name, c in counts.most_common(25):
    print(f"{100.0 * c / total:5.1f}%  {name}")
print(f"({total} samples)")
