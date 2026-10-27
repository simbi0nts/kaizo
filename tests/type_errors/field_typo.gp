# expect: has no field nme
type Todo = { id: Int, name: String } end
fn label(t: Todo) -> String
  t.nme
end
