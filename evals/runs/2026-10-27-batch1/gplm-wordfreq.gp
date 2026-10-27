type Entry = { word: String, count: Int } end

fn is_letter(b: Int) -> Bool
  or(and(ge(b, 65), le(b, 90)), and(ge(b, 97), le(b, 122)))
end

fn scan(s: String, i: Int, n: Int, start: Int, acc: List[String]) -> List[String]
  if ge(i, n) then
    if lt(start, 0) then acc else list_cons(str_lower(str_slice(s, start, n)), acc) end
  elif is_letter(str_byte(s, i)) then
    if lt(start, 0) then scan(s, add(i, 1), n, i, acc) else scan(s, add(i, 1), n, start, acc) end
  else
    if lt(start, 0) then
      scan(s, add(i, 1), n, -1, acc)
    else
      scan(s, add(i, 1), n, -1, list_cons(str_lower(str_slice(s, start, i)), acc))
    end
  end
end

fn words(s: String) -> List[String]
  list_reverse(scan(s, 0, str_len(s), -1, []))
end

fn count_runs(ws: List[String], acc: List[Entry]) -> List[Entry]
  match ws
    case [] -> list_reverse(acc)
    case [w, ..rest] ->
      match acc
        case [e, ..more] ->
          if eq(e.word, w) then
            count_runs(rest, list_cons({ e with count: add(e.count, 1) }, more))
          else
            count_runs(rest, list_cons(Entry { word: w, count: 1 }, acc))
          end
        case [] -> count_runs(rest, [Entry { word: w, count: 1 }])
      end
  end
end

fn before(a: Entry, b: Entry) -> Bool
  or(gt(a.count, b.count), and(eq(a.count, b.count), lt(a.word, b.word)))
end

fn format_entry(e: Entry) -> String
  str_cat(show(e.count), str_cat(" ", e.word))
end

fn top_words(text: String) -> List[String]
  let sorted = list_sort(words(text))
  let entries = count_runs(sorted, [])
  let ranked = list_sort_by(entries, fn(a, b) before(a, b) end)
  let top = list_slice(ranked, 0, min(10, list_len(ranked)))
  list_map(top, fn(e) format_entry(e) end)
end

fn print_lines(ls: List[String]) -> Unit ! [io]
  match ls
    case [] -> Unit
    case [l, ..rest] ->
      println(l)
      print_lines(rest)
  end
end

fn main() -> Unit ! [io, fs]
  match args()
    case [] ->
      println("usage: wordfreq <file>")
      exit(2)
    case [path, .._] ->
      match read_file(path)
        case Err(_) ->
          println(str_cat("error: cannot read ", path))
          exit(1)
        case Ok(text) -> print_lines(top_words(text))
      end
  end
end

test "words splits on non-letters"
  expect_eq(words("don't stop-2go"), ["don", "t", "stop", "go"])
end

test "empty and letterless text"
  expect_eq(top_words(""), [])
  expect_eq(top_words("123 !!! 456\n"), [])
end

test "example ranking"
  expect_eq(top_words("The cat and the hat. The cat sat!\nA hat, a cat; THE END.\n"),
    ["4 the", "3 cat", "2 a", "2 hat", "1 and", "1 end", "1 sat"])
end

test "ties ordered by word and limited to ten"
  expect_eq(top_words("l k j i h g f e d c b a"),
    ["1 a", "1 b", "1 c", "1 d", "1 e", "1 f", "1 g", "1 h", "1 i", "1 j"])
end
