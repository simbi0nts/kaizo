# expect: hint: Option has Some/None, Result has Ok/Err
fn f(o: Option[Int]) -> Result[Int, String]
  let x = try o
  Ok(x)
end
fn main() -> Unit ! [io] Unit end
