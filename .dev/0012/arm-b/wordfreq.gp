
type Entry = { word: String, count: Int } end

fn is_letter(b: Int) -> Bool
  or(and(ge(b, 65), le(b, 90)), and(ge(b, 97), le(b, 122)))
end

fn tokenize(s: String, i: Int, n: Int, start: Int, acc: List[String]) -> List[String]
  if ge(i, n) then
    if ge(start, 0) then
      list_reverse(list_cons(str_lower(str_slice(s, start, n)), acc))
    else
      list_reverse(acc)
    end
  elif is_letter(str_byte(s, i)) then
    tokenize(s, add(i, 1), n, if lt(start, 0) then
      i
    else
      start
    end, acc)
  elif ge(start, 0) then
    tokenize(s, add(i, 1), n, -1, list_cons(str_lower(str_slice(s, start, i)), acc))
  else
    tokenize(s, add(i, 1), n, -1, acc)
  end
end

fn split_words(s: String) -> List[String]
  tokenize(s, 0, str_len(s), -1, [])
end

fn count_runs(l: List[String], cur: String, cnt: Int, acc: List[Entry]) -> List[Entry]
  match l
    case [] ->
      list_reverse(list_cons(Entry { word: cur, count: cnt }, acc))
    case [w, ..rest] ->
      if eq(w, cur) then
        count_runs(rest, cur, add(cnt, 1), acc)
      else
        count_runs(rest, w, 1, list_cons(Entry { word: cur, count: cnt }, acc))
      end
  end
end

fn count_words(words: List[String]) -> List[Entry]
  match list_sort(words)
    case [] ->
      []
    case [w, ..rest] ->
      count_runs(rest, w, 1, [])
  end
end

fn before(a: Entry, b: Entry) -> Bool
  or(gt(a.count, b.count), and(eq(a.count, b.count), lt(a.word, b.word)))
end

fn merge(xs: List[Entry], ys: List[Entry], acc: List[Entry]) -> List[Entry]
  match xs
    case [] ->
      list_concat(list_reverse(acc), ys)
    case [x, ..xr] ->
      match ys
        case [] ->
          list_concat(list_reverse(acc), xs)
        case [y, ..yr] ->
          if before(y, x) then
            merge(xs, yr, list_cons(y, acc))
          else
            merge(xr, ys, list_cons(x, acc))
          end
      end
  end
end

fn msort(l: List[Entry]) -> List[Entry]
  let n = list_len(l)
  if le(n, 1) then
    l
  else
    let h = div(n, 2)
    merge(msort(list_slice(l, 0, h)), msort(list_slice(l, h, n)), [])
  end
end

fn top_lines(text: String) -> List[String]
  let entries = msort(count_words(split_words(text)))
  let top = list_slice(entries, 0, min(10, list_len(entries)))
  list_map(top, fn(e)
    str_cat(str_cat(show(e.count), " "), e.word)
  end)
end

fn main() -> Unit ! [io, fs]
  let a = args()
  match a
    case [] ->
      println("usage: wordfreq <file>")
      exit(2)
      Unit
    case [p, .._] ->
      match read_file(p)
        case Err(_) ->
          println(str_cat("error: cannot read ", p))
          exit(1)
          Unit
        case Ok(text) ->
          let lines = top_lines(text)
          if gt(list_len(lines), 0) then
            println(str_join(lines, "\n"))
          else
            Unit
          end
      end
  end
end

test "split words on non-letters and lower-case them"
  expect_eq(split_words("Don't stop-me 42 NOW!x"), ["don", "t", "stop", "me", "now", "x"])
  expect_eq(split_words("123 ... !!"), [])
end

test "count words"
  expect_eq(count_words(["b", "a", "b"]), [Entry { word: "a", count: 1 }, Entry { word: "b", count: 2 }])
end

test "ordering of the example"
  expect_eq(top_lines("The cat and the hat. The cat sat!\nA hat, a cat; THE END.\n"), ["4 the", "3 cat", "2 a", "2 hat", "1 and", "1 end", "1 sat"])
end

test "ties and limit of ten"
  expect_eq(top_lines("l k j i h g f e d c b a z z"), ["2 z", "1 a", "1 b", "1 c", "1 d", "1 e", "1 f", "1 g", "1 h", "1 i"])
end

