# topword: print the most frequent word from stdin (ties: earliest first occurrence)

type Entry = { word: String, count: Int } end

fn read_all(acc: List[String]) -> List[String] ! [io]
  match read_line()
    case Some(line) -> read_all(list_push(acc, line))
    case None -> acc
  end
end

fn line_words(line: String) -> List[String]
  let parts = list_map(str_split(line, " "), fn(p) str_trim(p) end)
  list_filter(parts, fn(p) ne(p, "") end)
end

fn bump(es: List[Entry], w: String) -> List[Entry]
  let words = list_map(es, fn(e) e.word end)
  if list_contains(words, w) then
    list_map(es, fn(e)
      if eq(e.word, w) then { e with count: add(e.count, 1) } else e end
    end)
  else
    list_push(es, Entry { word: w, count: 1 })
  end
end

fn main() -> Unit ! [io]
  let lines = read_all([])
  let words = list_fold(lines, [], fn(acc, l) list_concat(acc, line_words(l)) end)
  let entries = list_fold(words, [], fn(acc, w) bump(acc, w) end)
  let best = list_fold(entries, None, fn(acc, e)
    match acc
      case None -> Some(e)
      case Some(b) -> if gt(e.count, b.count) then Some(e) else acc end
    end
  end)
  match best
    case Some(b) -> println(b.word)
    case None -> Unit
  end
end
