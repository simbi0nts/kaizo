# ledger: account balances from transfers read on stdin

type Transfer = { src: String, dst: String, amt: Int } end
type Entry = { name: String, delta: Int } end

fn is_name_byte(b: Int) -> Bool
  or(or(and(ge(b, 48), le(b, 57)), and(ge(b, 65), le(b, 90))), or(and(ge(b, 97), le(b, 122)), eq(b, 95)))
end

fn name_from(s: String, i: Int, n: Int) -> Bool
  if ge(i, n) then
    true
  else
    if is_name_byte(str_byte(s, i)) then name_from(s, add(i, 1), n) else false end
  end
end

fn valid_name(s: String) -> Bool
  if eq(str_len(s), 0) then false else name_from(s, 0, str_len(s)) end
end

fn digits_from(s: String, i: Int, n: Int) -> Bool
  if ge(i, n) then
    true
  else
    let b = str_byte(s, i)
    if and(ge(b, 48), le(b, 57)) then digits_from(s, add(i, 1), n) else false end
  end
end

fn parse_amount(s: String) -> Option[Int]
  let n = str_len(s)
  if eq(n, 0) then
    None
  elif gt(n, 18) then
    None
  elif digits_from(s, 0, n) then
    match str_to_int(s)
      case Some(v) -> if gt(v, 0) then Some(v) else None end
      case None -> None
    end
  else
    None
  end
end

fn parse_line(line: String) -> Option[Transfer]
  match str_split(line, ",")
    case [a, b, c] ->
      if valid_name(a) then
        if valid_name(b) then
          if eq(a, b) then
            None
          else
            match parse_amount(c)
              case Some(v) -> Some(Transfer { src: a, dst: b, amt: v })
              case None -> None
            end
          end
        else
          None
        end
      else
        None
      end
    case _ -> None
  end
end

fn strip_eol(s: String) -> String
  let s1 = if str_ends(s, "\n") then str_slice(s, 0, sub(str_len(s), 1)) else s end
  if str_ends(s1, "\r") then str_slice(s1, 0, sub(str_len(s1), 1)) else s1 end
end

fn process(lines: List[String], i: Int, n: Int, acc: List[Entry]) -> Result[List[Entry], Int]
  if ge(i, n) then
    Ok(acc)
  else
    match list_get(lines, i)
      case None -> Ok(acc)
      case Some(raw) ->
        let line = strip_eol(raw)
        if eq(line, "") then
          process(lines, add(i, 1), n, acc)
        else
          match parse_line(line)
            case None -> Err(add(i, 1))
            case Some(t) ->
              let acc1 = list_push(acc, Entry { name: t.src, delta: sub(0, t.amt) })
              process(lines, add(i, 1), n, list_push(acc1, Entry { name: t.dst, delta: t.amt }))
          end
        end
    end
  end
end

fn fmt_line(name: String, sum: Int) -> String
  str_cat(name, str_cat(" ", show(sum)))
end

fn summarize(es: List[Entry], i: Int, n: Int, cur: String, sum: Int, out: List[String]) -> List[String]
  if ge(i, n) then
    if eq(cur, "") then out else list_push(out, fmt_line(cur, sum)) end
  else
    match list_get(es, i)
      case None -> out
      case Some(e) ->
        if eq(e.name, cur) then
          summarize(es, add(i, 1), n, cur, add(sum, e.delta), out)
        elif eq(cur, "") then
          summarize(es, add(i, 1), n, e.name, e.delta, out)
        else
          summarize(es, add(i, 1), n, e.name, e.delta, list_push(out, fmt_line(cur, sum)))
        end
    end
  end
end

fn ledger(lines: List[String]) -> Result[List[String], Int]
  match process(lines, 0, list_len(lines), [])
    case Err(n) -> Err(n)
    case Ok(es) ->
      let sorted = list_sort_by(es, fn(a, b) lt(a.name, b.name) end)
      Ok(summarize(sorted, 0, list_len(sorted), "", 0, []))
  end
end

fn read_all(acc: List[String]) -> List[String] ! [io]
  match read_line()
    case Some(l) -> read_all(list_push(acc, l))
    case None -> acc
  end
end

fn main() -> Unit ! [io]
  let lines = read_all([])
  match ledger(lines)
    case Err(n) ->
      println(str_cat("error: line ", show(n)))
      exit(1)
    case Ok(out) ->
      if gt(list_len(out), 0) then println(str_join(out, "\n")) else Unit end
      exit(0)
  end
end

test "example ledger"
  let r = ledger(["alice,bob,500", "bob,carol,200", "", "carol,alice,50"])
  expect_eq(r, Ok(["alice -450", "bob 300", "carol 150"]))
end

test "malformed lines are rejected"
  expect_eq(parse_line("a,b,0"), None)
  expect_eq(parse_line("a,a,5"), None)
  expect_eq(parse_line("a,b"), None)
  expect_eq(parse_line("a,b,1x"), None)
  expect_eq(parse_line("a-x,b,5"), None)
  expect_eq(parse_line(",b,5"), None)
  expect_eq(parse_line("a_1,B2,7"), Some(Transfer { src: "a_1", dst: "B2", amt: 7 }))
end

test "error line counts empty lines"
  expect_eq(ledger(["a,b,1", "", "a,b,"]), Err(3))
  expect_eq(ledger([]), Ok([]))
end

test "names are validated"
  expect(valid_name("abc_09"), "valid")
  expect(not(valid_name("")), "empty")
  expect(not(valid_name("a b")), "space")
end
