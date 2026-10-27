# Snake — test project 1. Pure game logic + a thin effectful loop.
# Run: kaizo run apps/snake/main.gp [--width N] [--height N] [--tick MS]

import rand

type Dir = Up | Down | Left | Right end
type Pos = { x: Int, y: Int } end
type Status = Playing | Dead | Quit end

# body: head first. dir: last direction moved. next: direction for the next tick.
type Game = { w: Int, h: Int, body: List[Pos], dir: Dir, next: Dir, food: Pos, score: Int, rng: Rng, status: Status } end
type Placed = { pos: Pos, rng: Rng } end

# ---------- pure logic ----------

fn opposite(a: Dir, b: Dir) -> Bool
  match a
    case Up -> eq(b, Down)
    case Down -> eq(b, Up)
    case Left -> eq(b, Right)
    case Right -> eq(b, Left)
  end
end

# reversing into the neck is ignored; compared with the direction actually moved
fn turn(g: Game, d: Dir) -> Game
  if opposite(g.dir, d) then g else { g with next: d } end
end

fn step_pos(p: Pos, d: Dir) -> Pos
  match d
    case Up -> { p with y: sub(p.y, 1) }
    case Down -> { p with y: add(p.y, 1) }
    case Left -> { p with x: sub(p.x, 1) }
    case Right -> { p with x: add(p.x, 1) }
  end
end

fn head_of(g: Game) -> Pos
  match g.body
    case [h, .._] -> h
    case [] -> panic("snake has no body")
  end
end

fn inside(g: Game, p: Pos) -> Bool
  and(and(ge(p.x, 0), lt(p.x, g.w)), and(ge(p.y, 0), lt(p.y, g.h)))
end

# food goes on a random free cell; off the board (-1, -1) when the board is full
fn place_food(w: Int, h: Int, body: List[Pos], r: Rng) -> Placed
  let cells = list_map(list_range(0, mul(w, h)), fn(i) Pos { x: mod(i, w), y: div(i, w) } end)
  let free = list_filter(cells, fn(c) not(list_contains(body, c)) end)
  let roll = rand.below(r, list_len(free))
  match list_get(free, roll.value)
    case Some(p) -> Placed { pos: p, rng: roll.rng }
    case None -> Placed { pos: Pos { x: -1, y: -1 }, rng: roll.rng }
  end
end

fn new_game(w: Int, h: Int, r: Rng) -> Game
  let cy = div(h, 2)
  let cx = div(w, 2)
  let body = [Pos { x: cx, y: cy }, Pos { x: sub(cx, 1), y: cy }, Pos { x: sub(cx, 2), y: cy }]
  let placed = place_food(w, h, body, r)
  Game { w: w, h: h, body: body, dir: Right, next: Right, food: placed.pos, score: 0, rng: placed.rng, status: Playing }
end

fn tick(g: Game) -> Game
  let d = g.next
  let head = step_pos(head_of(g), d)
  let eating = eq(head, g.food)
  # when not eating, the tail cell is vacated in the same tick, so it is a legal target
  let rest = if eating then g.body else list_slice(g.body, 0, sub(list_len(g.body), 1)) end
  if or(not(inside(g, head)), list_contains(rest, head)) then
    { g with status: Dead, dir: d }
  elif eating then
    let grown = list_cons(head, g.body)
    let placed = place_food(g.w, g.h, grown, g.rng)
    { g with body: grown, dir: d, score: add(g.score, 1), food: placed.pos, rng: placed.rng }
  else
    { g with body: list_cons(head, rest), dir: d }
  end
end

fn key_dir(k: String) -> Option[Dir]
  match str_lower(k)
    case "up" -> Some(Up)
    case "w" -> Some(Up)
    case "down" -> Some(Down)
    case "s" -> Some(Down)
    case "left" -> Some(Left)
    case "a" -> Some(Left)
    case "right" -> Some(Right)
    case "d" -> Some(Right)
    case _ -> None
  end
end

# apply one key press to the game
fn on_key(g: Game, k: String) -> Game
  if eq(str_lower(k), "q") then
    { g with status: Quit }
  else
    match key_dir(k)
      case Some(d) -> turn(g, d)
      case None -> g
    end
  end
end

fn cell(g: Game, p: Pos) -> String
  if eq(p, head_of(g)) then "@"
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
  if eq(k, "") then g else read_keys(on_key(g, k)) end
end

fn game_loop(g: Game, tick_ms: Int) -> Game ! [io, term, time]
  let started = now_ms()
  let g1 = read_keys(g)
  match g1.status
    case Playing ->
      let g2 = tick(g1)
      print(str_cat("\e[H", render(g2)))
      sleep_ms(max(0, sub(tick_ms, sub(now_ms(), started))))
      game_loop(g2, tick_ms)
    case Dead -> g1
    case Quit -> g1
  end
end

fn main() -> Unit ! [io, term, time]
  let a = args()
  let g = new_game(int_arg(a, "--width", 20), int_arg(a, "--height", 15), rand.seeded(now_ms()))
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
  { new_game(10, 6, rand.seeded(1)) with food: Pos { x: 0, y: 0 } }
end

test "starts with length 3 moving right"
  let g = fixed_game()
  expect_eq(list_len(g.body), 3)
  expect_eq(g.dir, Right)
  expect_eq(head_of(g), Pos { x: 5, y: 3 })
end

test "moves one cell per tick"
  let g = tick(fixed_game())
  expect_eq(head_of(g), Pos { x: 6, y: 3 })
  expect_eq(list_len(g.body), 3)
  expect_eq(g.status, Playing)
end

test "turn applies on next tick"
  let g = tick(on_key(fixed_game(), "up"))
  expect_eq(head_of(g), Pos { x: 5, y: 2 })
  expect_eq(g.dir, Up)
end

test "reverse is ignored"
  let g = tick(on_key(fixed_game(), "a"))
  expect_eq(head_of(g), Pos { x: 6, y: 3 })
end

test "two quick turns cannot reverse into the neck"
  # moving right; up then left within one tick: left is checked against the moved dir (right)
  let g = tick(on_key(on_key(fixed_game(), "up"), "left"))
  expect_eq(g.status, Playing)
  expect_eq(head_of(g), Pos { x: 5, y: 2 })
end

test "eating grows by one and scores"
  let g0 = { fixed_game() with food: Pos { x: 6, y: 3 } }
  let g = tick(g0)
  expect_eq(list_len(g.body), 4)
  expect_eq(g.score, 1)
  expect(not(list_contains(g.body, g.food)), "new food must be on a free cell")
  expect(inside(g, g.food), "new food must be on the board")
end

test "hitting a wall ends the game"
  let g = tick(tick(tick(tick(tick(fixed_game())))))
  expect_eq(g.status, Dead)
end

test "hitting itself ends the game"
  let body = [Pos { x: 2, y: 2 }, Pos { x: 3, y: 2 }, Pos { x: 3, y: 3 }, Pos { x: 2, y: 3 }, Pos { x: 1, y: 3 }]
  let g0 = { fixed_game() with body: body, dir: Left, next: Down }
  expect_eq(tick(g0).status, Dead)
end

test "moving into the vacating tail is allowed"
  let body = [Pos { x: 2, y: 2 }, Pos { x: 3, y: 2 }, Pos { x: 3, y: 3 }, Pos { x: 2, y: 3 }]
  let g0 = { fixed_game() with body: body, dir: Left, next: Down }
  expect_eq(tick(g0).status, Playing)
end

test "q quits"
  expect_eq(on_key(fixed_game(), "q").status, Quit)
end

test "food placement is reproducible with a seed"
  let a = place_food(10, 6, [], rand.seeded(99))
  let b = place_food(10, 6, [], rand.seeded(99))
  expect_eq(a.pos, b.pos)
end

test "full board puts food off the board"
  let all = list_map(list_range(0, 4), fn(i) Pos { x: mod(i, 2), y: div(i, 2) } end)
  expect_eq(place_food(2, 2, all, rand.seeded(3)).pos, Pos { x: -1, y: -1 })
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
