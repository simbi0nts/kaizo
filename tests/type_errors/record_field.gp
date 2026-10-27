# expect: expected String, got Int
type P = { x: Int, label: String } end
fn f() -> P
  P { x: 1, label: 2 }
end
