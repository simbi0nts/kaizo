# expect: error: try needs more statements after it
fn f(r: Result[Int, String]) -> Result[Int, String]
  try r
end
fn main() -> Unit ! [io] Unit end
