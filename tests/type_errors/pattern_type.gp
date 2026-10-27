# expect: 4:29: error: type mismatch: expected String, got Int
fn f(o: Option[Int]) -> Int
  match o
    case Some(s) -> str_len(s)
    case None -> 0
  end
end
