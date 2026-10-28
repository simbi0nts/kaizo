# expect: hint: try hands the Err on as the value of the enclosing block
fn f(r: Result[Int, String]) -> Int
  let x = try r
  add(x, 1)
end
fn main() -> Unit ! [io] Unit end
