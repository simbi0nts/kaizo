# todo-cli: a line-based todo manager.
# Commands on stdin: add <text> | done <n> | list | quit

type Todo = { text: String, done: Bool } end
type State = { items: List[Todo], quit: Bool } end
type Cmd = Add(String) | Done(Int) | List | Quit | Empty | Bad(String) end
type Outcome = { state: State, out: List[String] } end

let initial = State { items: [], quit: false }

fn after(s: String, prefix: String) -> String
  str_trim(str_slice(s, str_len(prefix), str_len(s)))
end

fn parse(line: String) -> Cmd
  let t = str_trim(line)
  if eq(t, "") then Empty
  elif eq(t, "list") then List
  elif eq(t, "quit") then Quit
  elif str_starts(t, "add ") then Add(after(t, "add "))
  elif str_starts(t, "done ") then
    match str_to_int(after(t, "done "))
      case Some(n) -> Done(n)
      case None -> Bad(t)
    end
  else Bad(t) end
end

fn render(t: Todo, n: Int) -> String
  let mark = if t.done then "[x]" else "[ ]" end
  str_cat(show(n), str_cat(". ", str_cat(mark, str_cat(" ", t.text))))
end

fn render_all(items: List[Todo], n: Int, acc: List[String]) -> List[String]
  match items
    case [] -> acc
    case [t, ..rest] -> render_all(rest, add(n, 1), list_push(acc, render(t, n)))
  end
end

fn mark_done(items: List[Todo], n: Int) -> Result[List[Todo], String]
  if lt(n, 1) then Err(str_cat("no such item: ", show(n)))
  else
    match list_get(items, sub(n, 1))
      case None -> Err(str_cat("no such item: ", show(n)))
      case Some(t) ->
        let before = list_slice(items, 0, sub(n, 1))
        let rest = list_slice(items, n, list_len(items))
        Ok(list_concat(before, list_cons({ t with done: true }, rest)))
    end
  end
end

fn reply(s: State, lines: List[String]) -> Outcome
  Outcome { state: s, out: lines }
end

fn step(s: State, c: Cmd) -> Outcome
  match c
    case Empty -> reply(s, [])
    case Quit -> reply({ s with quit: true }, ["bye"])
    case List ->
      if eq(list_len(s.items), 0) then reply(s, ["(empty)"])
      else reply(s, render_all(s.items, 1, [])) end
    case Add(text) ->
      if eq(text, "") then reply(s, ["error: add needs text"])
      else
        let items = list_push(s.items, Todo { text: text, done: false })
        reply({ s with items: items }, [str_cat("added ", show(list_len(items)))])
      end
    case Done(n) ->
      match mark_done(s.items, n)
        case Ok(items) -> reply({ s with items: items }, [str_cat("done ", show(n))])
        case Err(e) -> reply(s, [str_cat("error: ", e)])
      end
    case Bad(t) -> reply(s, [str_cat("error: unknown command: ", t)])
  end
end

# Run a whole script of lines through the pure state machine (used by tests).
fn run_lines(s: State, lines: List[String], acc: List[String]) -> List[String]
  match lines
    case [] -> acc
    case [line, ..rest] ->
      let o = step(s, parse(line))
      let acc2 = list_concat(acc, o.out)
      if o.state.quit then acc2 else run_lines(o.state, rest, acc2) end
  end
end

fn print_all(lines: List[String]) -> Unit ! [io]
  match lines
    case [] -> Unit
    case [l, ..rest] ->
      println(l)
      print_all(rest)
  end
end

fn loop(s: State) -> Unit ! [io]
  match read_line()
    case None -> Unit
    case Some(line) ->
      let o = step(s, parse(line))
      print_all(o.out)
      if o.state.quit then Unit else loop(o.state) end
  end
end

fn main() -> Unit ! [io]
  loop(initial)
end

test "parse commands"
  expect_eq(parse("add buy milk"), Add("buy milk"))
  expect_eq(parse("  done 2 "), Done(2))
  expect_eq(parse("list"), List)
  expect_eq(parse("quit"), Quit)
  expect_eq(parse(""), Empty)
  expect_eq(parse("done x"), Bad("done x"))
  expect_eq(parse("fly"), Bad("fly"))
end

test "add and list"
  let out = run_lines(initial, ["add a", "add b", "list"], [])
  expect_eq(out, ["added 1", "added 2", "1. [ ] a", "2. [ ] b"])
end

test "done marks item"
  let out = run_lines(initial, ["add a", "add b", "done 2", "list"], [])
  expect_eq(out, ["added 1", "added 2", "done 2", "1. [ ] a", "2. [x] b"])
end

test "errors keep state"
  let out = run_lines(initial, ["done 1", "add", "add a", "done 0", "done 5", "list"], [])
  expect_eq(out, ["error: no such item: 1", "error: unknown command: add", "added 1",
    "error: no such item: 0", "error: no such item: 5", "1. [ ] a"])
end

test "empty list and quit stops"
  let out = run_lines(initial, ["list", "quit", "add a"], [])
  expect_eq(out, ["(empty)", "bye"])
end
