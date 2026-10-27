# expect: expected List[String], got List[Int]
fn f(l: List[Int]) -> List[String]
  list_map(l, fn(x) add(x, 1) end)
end
