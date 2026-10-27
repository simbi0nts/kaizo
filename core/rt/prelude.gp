# Prelude: written in GPLM, embedded in the core, visible in every module unqualified.

type Option[T] = None | Some(T) end
type Result[T, E] = Ok(T) | Err(E) end

fn is_some(o: Option[T]) -> Bool
  match o
    case Some(_) -> true
    case None -> false
  end
end

fn unwrap_or(o: Option[T], default: T) -> T
  match o
    case Some(v) -> v
    case None -> default
  end
end

fn is_ok(r: Result[T, E]) -> Bool
  match r
    case Ok(_) -> true
    case Err(_) -> false
  end
end

fn max(a: Int, b: Int) -> Int
  if gt(a, b) then a else b end
end

fn min(a: Int, b: Int) -> Int
  if lt(a, b) then a else b end
end
