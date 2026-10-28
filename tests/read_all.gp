# Used by tests/ci_platform.sh: first line with read_line, the rest with read_all; prints sizes.
fn main() -> Unit ! [io]
  let first = unwrap_or(read_line(), "")
  let rest = read_all()
  println(str_cat(show(str_len(first)), " ", show(str_len(rest)), " ", show(str_len(read_all()))))
end
