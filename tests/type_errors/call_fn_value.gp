# expect: run uses io (through a function value), but run does not declare it
fn run(f: Fn(Int) -> Unit ! [io]) -> Unit
  f(1)
end
