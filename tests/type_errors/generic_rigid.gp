# expect: expected T, got Int
fn first(l: List[T], d: T) -> T
  match l
    case [x, .._] -> x
    case [] -> 0
  end
end
