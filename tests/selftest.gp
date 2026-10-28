# Self-test of the core language. Run: kaizo test core/selftest.gp

type Shape = Circle(Int) | Rect(Int, Int) | Empty end
type Pt = { x: Int, y: Int } end

let origin = Pt { x: 0, y: 0 }

fn area(s: Shape) -> Int
  match s
    case Circle(r) -> mul(3, mul(r, r))
    case Rect(w, h) -> mul(w, h)
    case Empty -> 0
  end
end

fn sum_to(n: Int, acc: Int) -> Int
  if eq(n, 0) then acc else sum_to(sub(n, 1), add(acc, n)) end
end

fn describe(l: List[Int]) -> String
  match l
    case [] -> "empty"
    case [x] -> str_cat("one: ", show(x))
    case [x, y, ..rest] -> str_join(["many", show(x), show(y), show(list_len(rest))], " ")
  end
end

fn sign(n: Int) -> String
  if lt(n, 0) then "neg" elif eq(n, 0) then "zero" else "pos" end
end

test "arithmetic, Euclidean div/mod"
  expect_eq(add(2, mul(3, 4)), 14)
  expect_eq(div(-7, 2), -4)
  expect_eq(mod(-7, 3), 2)
end

test "adt match"
  expect_eq(list_map([Circle(1), Rect(2, 3), Empty], area), [3, 6, 0])
end

test "records: build, field, update, equality"
  let p = { origin with x: 5 }
  expect_eq(p.x, 5)
  expect_eq(origin.x, 0)
  expect_eq(p, Pt { y: 0, x: 5 })
end

test "tail calls run in constant stack"
  expect_eq(sum_to(1000000, 0), 500000500000)
end

test "list patterns"
  expect_eq(describe([]), "empty")
  expect_eq(describe([7]), "one: 7")
  expect_eq(describe([1, 2, 3, 4]), "many 1 2 2")
end

test "if elif else"
  expect_eq(list_map([-3, 0, 9], sign), ["neg", "zero", "pos"])
end

test "lambdas capture"
  let k = 10
  let addk = fn(x) add(x, k) end
  expect_eq(list_map([1, 2], addk), [11, 12])
  expect_eq(list_fold([1, 2, 3], 0, fn(acc, x) add(acc, x) end), 6)
  expect_eq(list_filter(list_range(0, 10), fn(x) eq(mod(x, 3), 0) end), [0, 3, 6, 9])
end

test "list_sort_by: stable, empty, large"
  let byk = fn(a, b) lt(a.x, b.x) end
  let ps = [Pt { x: 2, y: 0 }, Pt { x: 1, y: 1 }, Pt { x: 2, y: 2 }, Pt { x: 1, y: 3 }, Pt { x: 0, y: 4 }]
  expect_eq(list_map(list_sort_by(ps, byk), fn(p) p.y end), [4, 1, 3, 0, 2])
  expect_eq(list_sort_by([], fn(a, b) lt(a, b) end), [])
  expect_eq(list_sort_by([5], fn(a, b) lt(a, b) end), [5])
  expect_eq(list_sort_by(["b", "c", "a"], fn(a, b) gt(a, b) end), ["c", "b", "a"])
  let big = list_map(list_range(0, 10000), fn(i) Pt { x: mod(mul(i, 7919), 100), y: i } end)
  let s = list_sort_by(big, byk)
  expect_eq(list_len(s), 10000)
  let ok = list_fold(list_range(1, 10000), true, fn(acc, i)
    let p = unwrap_or(list_get(s, sub(i, 1)), origin)
    let q = unwrap_or(list_get(s, i), origin)
    and(acc, or(lt(p.x, q.x), and(eq(p.x, q.x), lt(p.y, q.y))))
  end)
  expect(ok, "10k sorted by x, ties in input order")
end

fn try_int(s: String) -> Result[Int, String]
  let n = try str_to_int(s) else Err(str_cat("not a number: ", s))
  Ok(n)
end

fn try_sum(a: String, b: String) -> Result[Int, String]
  let x = try try_int(a)
  let y = try try_int(b)
  Ok(add(x, y))
end

fn try_unit(a: String) -> Result[String, String]
  try try_int(a)
  Ok("ok")
end

test "try"
  expect_eq(try_sum("2", "3"), Ok(5))
  expect_eq(try_sum("2", "x"), Err("not a number: x"))
  expect_eq(try_sum("y", "x"), Err("not a number: y"))
  expect_eq(try_unit("1"), Ok("ok"))
  expect_eq(try_unit("z"), Err("not a number: z"))
end

test "variadic builtins"
  expect_eq(add(1, 2, 3, 4), 10)
  expect_eq(mul(2, 3, 4), 24)
  expect_eq(str_cat("a", "b", show(1), "c"), "ab1c")
  expect(and(true, true, true), "and of three")
  expect(not(and(true, false, true)), "and with a false")
  expect(or(false, false, true), "or of three")
  expect_eq(bit_or(1, 2, 4), 7)
end

test "infix operators"
  let x = 7
  expect_eq((x + 3) * 2 - x % 3, 19)
  expect_eq(x-1, 6)
  expect_eq([x -1, -1, - x, 1 - -2], [6, -1, -7, 3])
  expect(x > 3 && !(x == 8) || false, "boolean operators")
  expect(1 + 2 * 3 == 7, "precedence")
  expect("a" < "b", "string compare")
  expect_eq(-7 / 2, -4)
  expect(x != 8 && x >= 7 && x <= 7, "comparisons")
end

test "strings"
  expect_eq(str_split("a,b,,c", ","), ["a", "b", "", "c"])
  expect_eq(str_find("hello", "ll"), Some(2))
  expect_eq(str_find("hello", "z"), None)
  expect_eq(str_slice("hello", 1, 3), "el")
  expect_eq(str_to_int(" 42 "), Some(42))
  expect_eq(unwrap_or(str_to_int("x"), -1), -1)
  expect_eq(show([Some("a"), None]), "[Some(\"a\"), None]")
end

test "bit operations"
  expect_eq(bit_and(12, 10), 8)
  expect_eq(bit_or(12, 10), 14)
  expect_eq(bit_xor(12, 10), 6)
  expect_eq(bit_shl(1, 40), 1099511627776)
  expect_eq(bit_shr(-16, 2), -4)
  expect_eq(bit_and(-1, 4294967295), 4294967295)
  expect_eq(list_map([1, 2], fn(x) bit_shl(x, 3) end), [8, 16])
  expect(ne(target(), ""), "target is known")
end

test "hex literals"
  expect_eq(0x1F, 31)
  expect_eq(0x1f, 0X1F)
  expect_eq(0xFADE0CC0, 4208856256)
  expect_eq(-0x1F, -31)
  expect_eq(-0xff, sub(0, 255))
  expect_eq(bit_and(0xFFFFFFFF, -1), 4294967295)
end
