# expect: 6:36: error: type mismatch: expected String, got Int
fn apply(f: Fn(Int) -> Int, x: Int) -> Int
  f(x)
end
fn main() -> Unit ! [io]
  println(show(apply(fn(s) str_len(s) end, 3)))
end
