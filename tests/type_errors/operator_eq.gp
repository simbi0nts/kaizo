# expect: hint: GPLM has no operators
fn f(x: Int) -> Int
  if x == 1 then 2 else 3 end
end
fn main() -> Unit ! [io] Unit end
