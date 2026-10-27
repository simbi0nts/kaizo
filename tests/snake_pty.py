#!/usr/bin/env python3
"""End-to-end Snake check in a pseudo-terminal: frames render, keys work, q and Ctrl+C
end the game, and the terminal settings (echo, canonical mode) are restored afterwards."""
import os, pty, sys, termios, time, select, signal

def run(cmd, keys, sig=None, wait=1.0):
    gate_r, gate_w = os.pipe()
    pid, fd = pty.fork()
    if pid == 0:
        os.read(gate_r, 1)  # wait until the parent has recorded the initial terminal state
        os.execvp(cmd[0], cmd)
    before = termios.tcgetattr(fd)
    os.write(gate_w, b"x")
    out = b""
    def drain(t):
        nonlocal out
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.05)
            if r:
                try: out += os.read(fd, 65536)
                except OSError: return
    drain(wait)
    for k in keys:
        os.write(fd, k); drain(0.4)
    if sig: os.kill(pid, sig)
    drain(1.0)
    _, status = os.waitpid(pid, 0)
    after = termios.tcgetattr(fd)
    return out.decode(errors="replace"), status, before, after

def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else ": " + detail))
    return ok

app = sys.argv[1:] or ["build/snake"]
good = True
out, st, before, after = run(app, [b"\x1b[B", b"s", b"q"])
good &= check("renders a bordered frame", "+--------------------+" in out, out[-300:])
good &= check("q ends with Game over", "Game over. Score:" in out, out[-300:])
good &= check("exit code 0 after q", os.waitstatus_to_exitcode(st) == 0, str(st))
good &= check("terminal lflag restored after q", before[3] == after[3])
good &= check("cursor shown again", "\x1b[?25h" in out)

out, st, before, after = run(app, [], sig=signal.SIGINT)
good &= check("Ctrl+C restores terminal", before[3] == after[3])

out, st, before, after = run(app + ["--tick", "20"], [], wait=1.5)
good &= check("snake dies at the wall on its own", "Game over. Score:" in out, out[-200:])  # food may lie on its path
sys.exit(0 if good else 1)
