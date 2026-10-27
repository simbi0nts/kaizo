# Snake with a window (X11). Same game logic as the terminal version (libs/snake).
# Run: kaizo run apps/snake-gui/main.gp      keys: arrows/WASD move, r restart, q/Esc quit

import rand
import snake
import x11

let cell = 24
let cols = 20
let rows = 15
let bar = 36
let tick_ms = 130

let c_bg = 0x14181C
let c_grid = 0x1C2228
let c_food = 0xE5484D
let c_body = 0x46A758
let c_head = 0x99D52A
let c_text = 0xEDEEF0
let c_dim = 0x7E868C

fn width() -> Int
  mul(cols, cell)
end

fn height() -> Int
  add(mul(rows, cell), bar)
end

fn cell_rect(p: Pos, inset: Int) -> Rect
  Rect { x: add(mul(p.x, cell), inset), y: add(add(bar, mul(p.y, cell)), inset), w: sub(cell, mul(2, inset)), h: sub(cell, mul(2, inset)) }
end

# the whole frame as X requests (pure)
fn frame(x: Draw, g: Game) -> List[String]
  let checker = list_filter(list_map(list_range(0, mul(cols, rows)), fn(i) Pos { x: mod(i, cols), y: div(i, cols) } end), fn(p) eq(mod(add(p.x, p.y), 2), 0) end)
  let body = match g.body
    case [_, ..rest] -> rest
    case [] -> []
  end
  let status = match g.status
    case Playing -> "arrows/WASD move   q quits"
    case Dead -> "Game over!   r restart   q quit"
    case Quit -> ""
  end
  [x11.fill(x, c_bg, [Rect { x: 0, y: 0, w: width(), h: height() }]),
   x11.fill(x, c_grid, list_map(checker, fn(p) cell_rect(p, 0) end)),
   x11.fill(x, c_food, if ge(g.food.x, 0) then [cell_rect(g.food, 4)] else [] end),
   x11.fill(x, c_body, list_map(body, fn(p) cell_rect(p, 2) end)),
   x11.fill(x, c_head, [cell_rect(snake.head_of(g), 1)]),
   x11.text(x, c_text, 12, 23, str_cat("Score: ", show(g.score))),
   x11.text(x, if eq(g.status, Dead) then c_food else c_dim end, 120, 23, status)]
end

fn on_event(g: Game, e: XEvent) -> Game
  match e
    case XKey(k) ->
      if eq(k, "esc") then { g with status: Quit }
      elif and(eq(k, "r"), eq(g.status, Dead)) then snake.new_game(cols, rows, g.rng)
      else snake.on_key(g, k) end
    case XClosed -> { g with status: Quit }
    case _ -> g
  end
end

fn redraw_needed(events: List[XEvent]) -> Bool
  list_contains(events, XExpose)
end

fn game_loop(x: X, g: Game) -> Game ! [net, time]
  let started = now_ms()
  let polled = x11.poll(x)
  let g1 = list_fold(polled.events, g, on_event)
  match g1.status
    case Quit -> g1
    case Playing ->
      let g2 = snake.tick(g1)
      x11.send(polled.x, frame(polled.x.draw, g2))
      sleep_ms(max(0, sub(tick_ms, sub(now_ms(), started))))
      game_loop(polled.x, g2)
    case Dead ->
      x11.send(polled.x, frame(polled.x.draw, g1))
      sleep_ms(50)
      game_loop(polled.x, g1)
  end
end

fn main() -> Unit ! [io, fs, net, time]
  match x11.open()
    case Err(e) -> println(str_cat("cannot open the display: ", e))
    case Ok(x0) ->
      let x = x11.window(x0, width(), height(), "Kaizo Snake")
      let final = game_loop(x, snake.new_game(cols, rows, rand.seeded(now_ms())))
      x11.close(x)
      println(str_cat("Game over. Score: ", show(final.score)))
  end
end

test "frame draws background, cells, snake, food and text"
  let g = snake.new_game(cols, rows, rand.seeded(1))
  expect_eq(list_len(frame(Draw { win: 2, gc: 3 }, g)), 7)
end

test "r restarts only after game over, esc quits"
  let g = snake.new_game(cols, rows, rand.seeded(1))
  expect_eq(on_event(g, XKey("r")).status, Playing)
  expect_eq(on_event({ g with status: Dead, score: 5 }, XKey("r")).score, 0)
  expect_eq(on_event(g, XKey("esc")).status, Quit)
  expect_eq(on_event(g, XClosed).status, Quit)
end
