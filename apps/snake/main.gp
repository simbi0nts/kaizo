# Snake — test project 1. Pure game logic + a thin effectful loop.
# Run: kaizo run apps/snake/main.gp [--width N] [--height N] [--tick MS]

import rand
import snake

fn cell(g: Game, p: Pos) -> String
  if eq(p, snake.head_of(g)) then "@"
  elif list_contains(g.body, p) then "o"
  elif eq(p, g.food) then "*"
  else " "
  end
end

fn render(g: Game) -> String
  let border = str_join(["+", str_repeat("-", g.w), "+"], "")
  let rows = list_map(list_range(0, g.h), fn(y)
    let cells = list_map(list_range(0, g.w), fn(x) cell(g, Pos { x: x, y: y }) end)
    str_join(["|", str_join(cells, ""), "|"], "")
  end)
  let footer = str_join(["Score: ", show(g.score), "   arrows/WASD move, q quits"], "")
  str_join(list_concat(list_concat([border], rows), [border, footer]), "\n")
end

# --flag N in the argument list, or the default
fn int_arg(args: List[String], flag: String, default: Int) -> Int
  match args
    case [f, v, ..rest] ->
      if eq(f, flag) then unwrap_or(str_to_int(v), default) else int_arg(list_cons(v, rest), flag, default) end
    case _ -> default
  end
end

# ---------- effects ----------

fn read_keys(g: Game) -> Game ! [term]
  let k = term_key()
  if eq(k, "") then g else read_keys(snake.on_key(g, k)) end
end

fn game_loop(g: Game, tick_ms: Int) -> Game ! [io, term, time]
  let started = now_ms()
  let g1 = read_keys(g)
  match g1.status
    case Playing ->
      let g2 = snake.tick(g1)
      print(str_cat("\e[H", render(g2)))
      sleep_ms(max(0, sub(tick_ms, sub(now_ms(), started))))
      game_loop(g2, tick_ms)
    case Dead -> g1
    case Quit -> g1
  end
end

fn main() -> Unit ! [io, term, time]
  let a = args()
  let g = snake.new_game(int_arg(a, "--width", 20), int_arg(a, "--height", 15), rand.seeded(now_ms()))
  match term_raw()
    case Err(e) -> println(str_cat("snake needs an interactive terminal: ", e))
    case Ok(_) ->
      print(str_cat("\e[2J\e[H", render(g)))
      let final = game_loop(g, int_arg(a, "--tick", 150))
      term_restore()
      println(str_cat("\nGame over. Score: ", show(final.score)))
  end
end

# ---------- tests ----------

fn fixed_game() -> Game
  { snake.new_game(10, 6, rand.seeded(1)) with food: Pos { x: 0, y: 0 } }
end

test "render has border, rows and score"
  let lines = str_split(render(fixed_game()), "\n")
  expect_eq(list_len(lines), 9)
  expect_eq(list_get(lines, 0), Some("+----------+"))
  expect_eq(list_get(lines, 4), Some("|   oo@    |"))
end

test "int_arg"
  expect_eq(int_arg(["--tick", "80", "--width", "30"], "--width", 20), 30)
  expect_eq(int_arg(["--width"], "--width", 20), 20)
  expect_eq(int_arg(["--width", "x"], "--width", 20), 20)
end
