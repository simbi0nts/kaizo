type P = { x: Int, y: Int } end
type G = { body: List[P], dir: Int, food: P, score: Int, rng: Int } end
type St = { g: G, games: Int, total: Int, sum: Int } end

let gw = 32
let gh = 24

fn next(r: Int) -> Int
  (r * 1103515245 + 12345) % 2147483648
end

fn step(p: P, d: Int) -> P
  if d == 0 then P { x: p.x, y: p.y - 1 }
  elif d == 1 then P { x: p.x + 1, y: p.y }
  elif d == 2 then P { x: p.x, y: p.y + 1 }
  else P { x: p.x - 1, y: p.y } end
end

fn place(body: List[P], r: Int) -> G
  let r1 = next(r)
  let r2 = next(r1)
  let f = P { x: r1 % gw, y: r2 % gh }
  if list_contains(body, f) then place(body, r2)
  else G { body: body, dir: 1, food: f, score: 0, rng: r2 } end
end

fn new_game(r: Int) -> G
  place([P { x: 16, y: 12 }, P { x: 15, y: 12 }, P { x: 14, y: 12 }], r)
end

fn head(g: G) -> P
  unwrap_or(list_get(g.body, 0), P { x: 0, y: 0 })
end

fn free(g: G, p: P) -> Bool
  p.x >= 0 && p.x < gw && p.y >= 0 && p.y < gh && !list_contains(list_slice(g.body, 0, list_len(g.body) - 1), p)
end

fn choose(g: G, cands: List[Int]) -> Int
  match cands
    case [] -> g.dir
    case [d, ..rest] ->
      if d != (g.dir + 2) % 4 && free(g, step(head(g), d)) then d else choose(g, rest) end
  end
end

fn candidates(g: G) -> List[Int]
  let h = head(g)
  let hx = if g.food.x > h.x then [1] elif g.food.x < h.x then [3] else [] end
  let vy = if g.food.y > h.y then [2] elif g.food.y < h.y then [0] else [] end
  list_concat(list_concat(hx, vy), [0, 1, 2, 3])
end

fn tick(s: St) -> St
  let g = s.g
  let d = choose(g, candidates(g))
  let nh = step(head(g), d)
  if !free(g, nh) then
    let ng = new_game(g.rng)
    let h = head(ng)
    St { g: ng, games: s.games + 1, total: s.total + g.score, sum: (s.sum * 31 + h.x * 32 + h.y) % 1000000007 }
  elif nh == g.food then
    let grown = list_cons(nh, g.body)
    let placed = place(grown, g.rng)
    let ng = { placed with dir: d, score: g.score + 1 }
    St { g: ng, games: s.games, total: s.total, sum: (s.sum * 31 + nh.x * 32 + nh.y) % 1000000007 }
  else
    let moved = list_cons(nh, list_slice(g.body, 0, list_len(g.body) - 1))
    St { g: { g with body: moved, dir: d }, games: s.games, total: s.total, sum: (s.sum * 31 + nh.x * 32 + nh.y) % 1000000007 }
  end
end

fn run(s: St, n: Int) -> St
  if n == 0 then s else run(tick(s), n - 1) end
end

fn main() -> Unit ! [io]
  let n = unwrap_or(str_to_int(unwrap_or(list_get(args(), 0), "200000")), 200000)
  let s = run(St { g: new_game(42), games: 0, total: 0, sum: 0 }, n)
  println(str_cat("games ", show(s.games), " total ", show(s.total + s.g.score), " checksum ", show(s.sum)))
end
