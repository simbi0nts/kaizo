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

test "strings"
  expect_eq(str_split("a,b,,c", ","), ["a", "b", "", "c"])
  expect_eq(str_find("hello", "ll"), Some(2))
  expect_eq(str_find("hello", "z"), None)
  expect_eq(str_slice("hello", 1, 3), "el")
  expect_eq(str_to_int(" 42 "), Some(42))
  expect_eq(unwrap_or(str_to_int("x"), -1), -1)
  expect_eq(show([Some("a"), None]), "[Some(\"a\"), None]")
end
