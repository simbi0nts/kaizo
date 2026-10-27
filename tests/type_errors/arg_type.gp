# expect: expected Int, got String
fn twice(n: Int) -> Int
  mul(n, 2)
end
fn main() -> Unit ! [io]
  println(show(twice("3")))
end
