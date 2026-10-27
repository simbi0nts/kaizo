#!/usr/bin/env python3
"""Run the test_* functions of a candidate Python file (without starting its main program)."""
import importlib.util, sys, traceback
spec = importlib.util.spec_from_file_location("candidate", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
except SystemExit:
    print("the file runs its program on import (guard it with if __name__ == '__main__')"); sys.exit(1)
tests = [n for n in dir(mod) if n.startswith("test_") and callable(getattr(mod, n))]
failed = 0
for n in tests:
    try:
        getattr(mod, n)()
    except Exception:
        failed += 1; print(f"FAIL {n}"); traceback.print_exc(limit=2)
print(f"{len(tests) - failed} passed, {failed} failed")
sys.exit(1 if failed or not tests else 0)
