# wordfreq: print the 10 most frequent words of a text file

type Entry = { word: String, count: Int } end
type Acc = { cur: String, cnt: Int, out: List[Entry] } end

fn is_letter(b: Int) -> Bool
  or(and(ge(b, 65), le(b, 90)), and(ge(b, 97), le(b, 122)))
end

fn scan(s: String, i: Int, n: Int, start: Int, acc: List[String]) -> List[String]
  if ge(i, n) then
    if ge(start, 0) then list_cons(str_lower(str_slice(s, start, n)), acc) else acc end
  else
    let b = str_byte(s, i)
    if is_letter(b) then
      if ge(start, 0) then scan(s, add(i, 1), n, start, acc) else scan(s, add(i, 1), n, i, acc) end
    elif ge(start, 0) then
      scan(s, add(i, 1), n, -1, list_cons(str_lower(str_slice(s, start, i)), acc))
    else
      scan(s, add(i, 1), n, -1, acc)
    end
  end
end

fn split_words(s: String) -> List[String]
  list_reverse(scan(s, 0, str_len(s), -1, []))
end

fn flush(a: Acc) -> List[Entry]
  if gt(a.cnt, 0) then list_cons(Entry { word: a.cur, count: a.cnt }, a.out) else a.out end
end

# entries in ascending word order
fn count_words(words: List[String]) -> List[Entry]
  let sorted = list_sort(words)
  let start = Acc { cur: "", cnt: 0, out: [] }
  let fin = list_fold(sorted, start, fn(a, x)
    if and(gt(a.cnt, 0), eq(x, a.cur)) then
      { a with cnt: add(a.cnt, 1) }
    else
      Acc { cur: x, cnt: 1, out: flush(a) }
    end
  end)
  list_reverse(flush(fin))
end

fn make_key(e: Entry) -> String
  let d = show(sub(9999999, e.count))
  str_cat(str_cat(str_repeat("0", sub(7, str_len(d))), d), str_cat(" ", e.word))
end

fn parse_digits(s: String, i: Int, n: Int, acc: Int) -> Int
  if ge(i, n) then acc else parse_digits(s, add(i, 1), n, add(mul(acc, 10), sub(str_byte(s, i), 48))) end
end

fn decode_key(k: String) -> Entry
  Entry { word: str_slice(k, 8, str_len(k)), count: sub(9999999, parse_digits(k, 0, 7, 0)) }
end

# count descending, then word ascending
fn rank(entries: List[Entry]) -> List[Entry]
  let keys = list_sort(list_map(entries, fn(e) make_key(e) end))
  list_map(keys, fn(k) decode_key(k) end)
end

fn top(entries: List[Entry], k: Int) -> List[Entry]
  list_slice(entries, 0, min(k, list_len(entries)))
end

fn word_freq(text: String) -> List[Entry]
  top(rank(count_words(split_words(text))), 10)
end

fn print_entries(es: List[Entry]) -> Unit ! [io]
  match es
    case [] -> Unit
    case [e, ..rest] ->
      println(str_cat(str_cat(show(e.count), " "), e.word))
      print_entries(rest)
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
        case Ok(text) ->
          print_entries(word_freq(text))
      end
  end
end

test "split words"
  expect_eq(split_words("don't Stop-NOW 42x"), ["don", "t", "stop", "now", "x"])
  expect_eq(split_words(""), [])
  expect_eq(split_words("123 !!"), [])
end

test "count words"
  expect_eq(count_words(["b", "a", "b"]), [Entry { word: "a", count: 1 }, Entry { word: "b", count: 2 }])
  expect_eq(count_words([]), [])
end

test "ordering"
  let r = rank([Entry { word: "b", count: 2 }, Entry { word: "ab", count: 2 }, Entry { word: "a", count: 2 }, Entry { word: "z", count: 5 }])
  expect_eq(r, [Entry { word: "z", count: 5 }, Entry { word: "a", count: 2 }, Entry { word: "ab", count: 2 }, Entry { word: "b", count: 2 }])
end

test "example"
  let got = word_freq("The cat and the hat. The cat sat!\nA hat, a cat; THE END.\n")
  expect_eq(got, [Entry { word: "the", count: 4 }, Entry { word: "cat", count: 3 }, Entry { word: "a", count: 2 }, Entry { word: "hat", count: 2 }, Entry { word: "and", count: 1 }, Entry { word: "end", count: 1 }, Entry { word: "sat", count: 1 }])
end
