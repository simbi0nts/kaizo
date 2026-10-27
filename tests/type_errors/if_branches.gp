# expect: expected Int, got String
fn f(c: Bool) -> Int
  if c then 1 else "one" end
end
