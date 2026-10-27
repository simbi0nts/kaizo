# expect: expected Int, got String
type Shape = Circle(Int) | Square(Int) end
fn f() -> Shape
  Circle("big")
end
