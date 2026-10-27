# expect: tick does not declare it
fn tick(xs: List[Int]) -> List[Int]
  list_map(xs, fn(x)
    println(show(x))
    x
  end)
end
