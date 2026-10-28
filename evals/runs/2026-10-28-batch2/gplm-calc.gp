  # calc: integer calculator in GPLM
  
  type Expr = Num(Int) | Neg(Expr) | Bin(Int, Expr, Expr) end
  type PR = { e: Expr, pos: Int } end
  
  fn byte_at(s: String, i: Int) -> Int
    if lt(i, str_len(s)) then str_byte(s, i) else -1 end
  end
  
  fn is_digit(c: Int) -> Bool
    and(ge(c, 48), le(c, 57))
  end
  
  fn skip_ws(s: String, i: Int) -> Int
    let c = byte_at(s, i)
    if or(eq(c, 32), or(eq(c, 9), eq(c, 13))) then skip_ws(s, add(i, 1)) else i end
  end
  
  fn parse_num(s: String, j: Int, acc: Int) -> PR
    let c = byte_at(s, j)
    if is_digit(c) then
      parse_num(s, add(j, 1), add(mul(acc, 10), sub(c, 48)))
    else
      PR { e: Num(acc), pos: j }
    end
  end
  
  fn parse_primary(s: String, i: Int) -> Result[PR, Int]
    let j = skip_ws(s, i)
    let c = byte_at(s, j)
    if is_digit(c) then
      Ok(parse_num(s, j, 0))
    elif eq(c, 40) then
      match parse_expr(s, add(j, 1))
        case Err(col) -> Err(col)
        case Ok(r) ->
          let k = skip_ws(s, r.pos)
          if eq(byte_at(s, k), 41) then
            Ok(PR { e: r.e, pos: add(k, 1) })
          else
            Err(add(k, 1))
          end
      end
    else
      Err(add(j, 1))
    end
  end
  
  fn parse_unary(s: String, i: Int) -> Result[PR, Int]
    let j = skip_ws(s, i)
    if eq(byte_at(s, j), 45) then
      match parse_unary(s, add(j, 1))
        case Err(col) -> Err(col)
        case Ok(r) -> Ok({ r with e: Neg(r.e) })
      end
    else
      parse_primary(s, j)
    end
  end
  
  fn term_rest(s: String, r: PR) -> Result[PR, Int]
    let j = skip_ws(s, r.pos)
    let c = byte_at(s, j)
    if or(eq(c, 42), or(eq(c, 47), eq(c, 37))) then
      match parse_unary(s, add(j, 1))
        case Err(col) -> Err(col)
        case Ok(r2) -> term_rest(s, PR { e: Bin(c, r.e, r2.e), pos: r2.pos })
      end
    else
      Ok(r)
    end
  end
  
  fn parse_term(s: String, i: Int) -> Result[PR, Int]
    match parse_unary(s, i)
      case Err(col) -> Err(col)
      case Ok(r) -> term_rest(s, r)
    end
  end
  
  fn expr_rest(s: String, r: PR) -> Result[PR, Int]
    let j = skip_ws(s, r.pos)
    let c = byte_at(s, j)
    if or(eq(c, 43), eq(c, 45)) then
      match parse_term(s, add(j, 1))
        case Err(col) -> Err(col)
        case Ok(r2) -> expr_rest(s, PR { e: Bin(c, r.e, r2.e), pos: r2.pos })
      end
    else
      Ok(r)
    end
  end
  
  fn parse_expr(s: String, i: Int) -> Result[PR, Int]
    match parse_term(s, i)
      case Err(col) -> Err(col)
      case Ok(r) -> expr_rest(s, r)
    end
  end
  
  fn parse_line(s: String) -> Result[Expr, Int]
    match parse_expr(s, 0)
      case Err(col) -> Err(col)
      case Ok(r) ->
        let k = skip_ws(s, r.pos)
        if eq(k, str_len(s)) then Ok(r.e) else Err(add(k, 1)) end
    end
  end
  
  fn abs_int(x: Int) -> Int
    if lt(x, 0) then sub(0, x) else x end
  end
  
  fn tdiv(a: Int, b: Int) -> Int
    let q = div(abs_int(a), abs_int(b))
    if ne(lt(a, 0), lt(b, 0)) then sub(0, q) else q end
  end
  
  fn trem(a: Int, b: Int) -> Int
    sub(a, mul(b, tdiv(a, b)))
  end
  
  fn apply_op(op: Int, x: Int, y: Int) -> Result[Int, String]
    if eq(op, 43) then Ok(add(x, y))
    elif eq(op, 45) then Ok(sub(x, y))
    elif eq(op, 42) then Ok(mul(x, y))
    elif eq(y, 0) then Err("error: division by zero")
    elif eq(op, 47) then Ok(tdiv(x, y))
    else Ok(trem(x, y))
    end
  end
  
  fn eval(ex: Expr) -> Result[Int, String]
    match ex
      case Num(n) -> Ok(n)
      case Neg(x) ->
        match eval(x)
          case Err(m) -> Err(m)
          case Ok(v) -> Ok(sub(0, v))
        end
      case Bin(op, a, b) ->
        match eval(a)
          case Err(m) -> Err(m)
          case Ok(x) ->
            match eval(b)
              case Err(m) -> Err(m)
              case Ok(y) -> apply_op(op, x, y)
            end
        end
    end
  end
  
  fn calc_line(line: String) -> Result[Int, String]
    match parse_line(line)
      case Err(col) -> Err(str_cat("error: syntax at ", show(col)))
      case Ok(ex) -> eval(ex)
    end
  end
  
  fn process(line: String) -> Bool ! [io]
    if eq(str_len(str_trim(line)), 0) then
      true
    else
      match calc_line(line)
        case Ok(v) ->
          println(show(v))
          true
        case Err(m) ->
          println(m)
          false
      end
    end
  end
  
  fn run(ok: Bool) -> Bool ! [io]
    match read_line()
      case None -> ok
      case Some(line) ->
        let r = process(line)
        run(and(ok, r))
    end
  end
  
  fn main() -> Unit ! [io]
    let ok = run(true)
    if ok then exit(0) else exit(1) end
  end
  
  test "precedence and parens"
    expect_eq(calc_line("1 + 2 * 3"), Ok(7))
    expect_eq(calc_line("(1+2)*3"), Ok(9))
    expect_eq(calc_line("-(4 - 10) % 4"), Ok(2))
    expect_eq(calc_line("8-3-2"), Ok(3))
    expect_eq(calc_line("2*3%4"), Ok(2))
  end
  
  test "truncating division"
    expect_eq(calc_line("-7/2"), Ok(-3))
    expect_eq(calc_line("-7%2"), Ok(-1))
    expect_eq(calc_line("7%-2"), Ok(1))
    expect_eq(calc_line("7 / (3 - 3)"), Err("error: division by zero"))
  end
  
  test "syntax errors"
    expect_eq(calc_line("2 *"), Err("error: syntax at 4"))
    expect_eq(calc_line("1 2"), Err("error: syntax at 3"))
    expect_eq(calc_line("(1"), Err("error: syntax at 3"))
    expect_eq(calc_line("1/0 +"), Err("error: syntax at 6"))
  end
  