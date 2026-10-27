You are writing a program in GPLM, a programming language. Its complete reference is below; you have
no other documentation and no internet. Write the program as ONE file and reply with the file only.

Rules of this exercise:
- You cannot run anything. After you answer, the orchestrator compiles and tests your file and may
  send you the compiler's diagnostics or a failing test's output; then answer with the corrected file.
- Command-line arguments: `args()` returns them without the program name.
- Read all of standard input with repeated `read_line()` (it returns `None` at the end).
- Exit codes: `exit(n)`.

--- GPLM reference ---
{LANGUAGE.md}
--- spec ---
{spec.md}
