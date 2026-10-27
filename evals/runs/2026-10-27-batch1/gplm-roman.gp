# roman: convert between decimal numbers and Roman numerals

fn to_roman_go(n: Int, vals: List[Int], syms: List[String], acc: String) -> String
  match vals
    case [] -> acc
    case [v, ..vr] ->
      match syms
        case [] -> acc
        case [s, ..sr] ->
          if ge(n, v) then
            to_roman_go(sub(n, v), vals, syms, str_cat(acc, s))
          else
            to_roman_go(n, vr, sr, acc)
          end
      end
  end
end

fn to_roman(n: Int) -> String
  to_roman_go(n,
    [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1],
    ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"],
    "")
end

fn is_digit(b: Int) -> Bool
  and(ge(b, 48), le(b, 57))
end

# returns -1 on any non-digit or when the value exceeds 4000
fn parse_dec(s: String, i: Int, acc: Int) -> Int
  if ge(i, str_len(s)) then
    acc
  else
    let b = str_byte(s, i)
    if is_digit(b) then
      let n = add(mul(acc, 10), sub(b, 48))
      if gt(n, 4000) then -1 else parse_dec(s, add(i, 1), n) end
    else
      -1
    end
  end
end

# value of a lower-case roman letter byte, 0 if not a roman letter
fn rv(b: Int) -> Int
  match b
    case 105 -> 1
    case 118 -> 5
    case 120 -> 10
    case 108 -> 50
    case 99 -> 100
    case 100 -> 500
    case 109 -> 1000
    case _ -> 0
  end
end

# returns -1 on an invalid character
fn parse_rom(s: String, i: Int, acc: Int) -> Int
  let n = str_len(s)
  if ge(i, n) then
    acc
  else
    let v = rv(str_byte(s, i))
    if eq(v, 0) then
      -1
    else
      let nx = if lt(add(i, 1), n) then rv(str_byte(s, add(i, 1))) else 0 end
      if lt(v, nx) then
        parse_rom(s, add(i, 1), sub(acc, v))
      else
        parse_rom(s, add(i, 1), add(acc, v))
      end
    end
  end
end

fn in_range(n: Int) -> Bool
  and(ge(n, 1), le(n, 3999))
end

fn convert(x: String) -> Option[String]
  if eq(str_len(x), 0) then
    None
  else
    let b = str_byte(x, 0)
    if is_digit(b) then
      let n = parse_dec(x, 0, 0)
      if in_range(n) then Some(to_roman(n)) else None end
    else
      let low = str_lower(x)
      let n = parse_rom(low, 0, 0)
      if and(in_range(n), eq(str_lower(to_roman(n)), low)) then
        Some(show(n))
      else
        None
      end
    end
  end
end

fn main() -> Unit ! [io]
  match args()
    case [x] ->
      match convert(x)
        case Some(out) ->
          println(out)
          exit(0)
        case None ->
          println(str_cat("error: invalid input ", x))
          exit(1)
      end
    case _ ->
      println("usage: roman <number|numeral>")
      exit(2)
  end
end

test "to_roman canonical"
  expect_eq(to_roman(1994), "MCMXCIV")
  expect_eq(to_roman(4), "IV")
  expect_eq(to_roman(3999), "MMMCMXCIX")
end

test "decimal conversions"
  expect_eq(convert("1994"), Some("MCMXCIV"))
  expect_eq(convert("0"), None)
  expect_eq(convert("4000"), None)
  expect_eq(convert("-5"), None)
  expect_eq(convert("+5"), None)
  expect_eq(convert(""), None)
end

test "roman conversions"
  expect_eq(convert("mcmxciv"), Some("1994"))
  expect_eq(convert("MMMCMXCIX"), Some("3999"))
  expect_eq(convert("IIII"), None)
  expect_eq(convert("VX"), None)
  expect_eq(convert("abc"), None)
end
