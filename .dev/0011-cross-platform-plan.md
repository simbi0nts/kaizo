# Step 0011 — Plan: Windows x64, macOS x86-64, macOS arm64
Date: 2026-10-27
Status: plan + phase A done

## Human request
"Make sure kaizo is compilable on other OS (macOS, Windows)." Chosen: Windows x64, macOS arm64,
macOS x86-64; verification on **GitHub Actions** (real macOS/Windows runners).

## Why this is more than a port
kaizo is self-hosted, so "kaizo runs on X" = "kaizo can emit programs for X" + cross-compile itself.
| | Linux x64 (today) | Windows x64 | macOS x86-64 | macOS arm64 |
|---|---|---|---|---|
| format | ELF | PE32+ | Mach-O | Mach-O |
| OS interface | raw syscalls | kernel32/ws2_32 imports (IAT) | libSystem via dyld (GOT, bind opcodes) | same |
| C ABI | — | Win64 (rcx,rdx,r8,r9 + shadow space) | SysV | AAPCS64 (x0..x7) |
| CPU | x86-64 | x86-64 | x86-64 | **arm64: new back end** |
| other | | console API, VEH commits heap pages, no fork | ASLR → position-independent code | + ad-hoc **code signature** (SHA-256) |

## Design
- **Target-independent IR** between codegen and machine code (registers named like x86, mapped to
  arm64 x0..x7, x26 = value stack, x27 = closure, x28 = heap, x29 = frame). Lowerings: `x64.gp`, `a64.gp`.
  arm64 keeps the same frame layout by using x26 as an 8-byte-granular value stack; real `sp` is only
  for C calls.
- **Position-independent code** everywhere (RIP-relative / ADRP), code and data in separate segments
  (RX / RW), and a tiny **self-relocation** pass at start-up for data pointers (needed for macOS ASLR;
  slide is 0 on Linux/Windows).
- **OS layer**: `core/rt/rt.gp` stays portable; `os_linux.gp`, `os_windows.gp`, `os_macos.gp` (+ small
  per-arch files) implement `os_*` functions. Foreign calls via intrinsics `prim_ccall("sym", [args])`
  / `prim_ccall32` (int result sign-extended); `"dll!sym"` picks a Windows DLL.
- New builtins: `bit_and bit_or bit_xor bit_shl bit_shr`, `target()` (compile target name).
- `kaizo build|run|test ... --target linux-x64|windows-x64|macos-x64|macos-arm64` (default = host).
- Tests on Windows: the test binary re-runs itself per test (no fork).
- CI: Linux builds everything (incl. cross-compiled kaizo for each OS); each OS runner runs its
  kaizo: all suites, self-compile, **cross-host fixpoint** (kaizo on Windows/macOS must produce the
  same bytes as the Linux cross build), hello-web over HTTP; Snake terminal test where a pty exists.

## Phases
A. bit ops + `target()` in the compiler → new seed (the compiler may only use features the seed knows)
B. IR + PIC + two segments + self-relocation + OS-layer split, Linux only → fixpoint → new seed
C. Windows x64 (PE writer, imports, Win64 calls, os_windows) — locally checked with objdump (pei-x86-64)
D. macOS x86-64 (Mach-O, dyld bind info, SHA-256 + code signature, os_macos) — checked by a Python verifier
E. arm64 lowering + macOS arm64
F. CI workflow, docs. Needs the human to create a GitHub repo and push.

## Local verification limits
No Wine/macOS/arm64 tools here (objdump knows only x86 + PE). macOS and arm64 are proven only on CI.
