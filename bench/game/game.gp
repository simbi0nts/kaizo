# Snake with arrays: occupancy grid + ring buffer, updated in place with list_set (see SPEC.md)
type Out = { games: Int, total: Int, sum: Int } end

let gw = 32
let gh = 24
let cap = 769
let big = 1000000007

fn next(r: Int) -> Int
  (r * 1103515245 + 12345) % 2147483648
end

fn at(body: List[Int], hi: Int, k: Int) -> Int
  list_get_or(body, (hi + k) % cap, 0)
end

fn free(occ: List[Bool], body: List[Int], hi: Int, len: Int, x: Int, y: Int) -> Bool
  if x < 0 || x >= gw || y < 0 || y >= gh then false
  elif x * gh + y == at(body, hi, len - 1) then true
  else !list_get_or(occ, x * gh + y, true) end
end

fn step_x(x: Int, d: Int) -> Int
  if d == 1 then x + 1 elif d == 3 then x - 1 else x end
end

fn step_y(y: Int, d: Int) -> Int
  if d == 0 then y - 1 elif d == 2 then y + 1 else y end
end

fn choose(occ: List[Bool], body: List[Int], hi: Int, len: Int, dir: Int, hx: Int, hy: Int, cands: List[Int]) -> Int
  match cands
    case [] -> dir
    case [d, ..rest] ->
      if d != (dir + 2) % 4 && free(occ, body, hi, len, step_x(hx, d), step_y(hy, d)) then d
      else choose(occ, body, hi, len, dir, hx, hy, rest) end
  end
end

fn new_game(rng: Int, games: Int, total: Int, sum: Int, n: Int) -> Out
  let occ = list_set(list_set(list_set(list_fill(gw * gh, false), 16 * gh + 12, true), 15 * gh + 12, true), 14 * gh + 12, true)
  let body = list_set(list_set(list_set(list_fill(cap, 0), 0, 16 * gh + 12), 1, 15 * gh + 12), 2, 14 * gh + 12)
  place(occ, body, 0, 3, 1, 0, rng, games, total, sum, n)
end

fn place(occ: List[Bool], body: List[Int], hi: Int, len: Int, dir: Int, score: Int, rng: Int, games: Int, total: Int, sum: Int, n: Int) -> Out
  let r1 = next(rng)
  let r2 = next(r1)
  let x = r1 % gw
  let y = r2 % gh
  if list_get_or(occ, x * gh + y, true) then place(occ, body, hi, len, dir, score, r2, games, total, sum, n)
  else run(occ, body, hi, len, dir, x, y, score, r2, games, total, sum, n) end
end

fn run(occ: List[Bool], body: List[Int], hi: Int, len: Int, dir: Int, fx: Int, fy: Int, score: Int, rng: Int, games: Int, total: Int, sum: Int, n: Int) -> Out
  if n == 0 then Out { games: games, total: total + score, sum: sum }
  else
    let h = at(body, hi, 0)
    let hx = h / gh
    let hy = h % gh
    let c1 = if fx > hx then [1] elif fx < hx then [3] else [] end
    let c2 = if fy > hy then [2] elif fy < hy then [0] else [] end
    let d = choose(occ, body, hi, len, dir, hx, hy, list_concat(list_concat(c1, c2), [0, 1, 2, 3]))
    let nx = step_x(hx, d)
    let ny = step_y(hy, d)
    if !free(occ, body, hi, len, nx, ny) then
      new_game(rng, games + 1, total + score, (sum * 31 + 16 * 32 + 12) % big, n - 1)
    else
      let nh = nx * gh + ny
      let s2 = (sum * 31 + nx * 32 + ny) % big
      let hi2 = (hi + cap - 1) % cap
      if nx == fx && ny == fy then
        place(list_set(occ, nh, true), list_set(body, hi2, nh), hi2, len + 1, d, score + 1, rng, games, total, s2, n - 1)
      else
        let tail = at(body, hi, len - 1)
        let occ2 = list_set(list_set(occ, tail, false), nh, true)
        run(occ2, list_set(body, hi2, nh), hi2, len, d, fx, fy, score, rng, games, total, s2, n - 1)
      end
    end
  end
end

fn main() -> Unit ! [io]
  let n = list_get_or(list_map(args(), fn(a) unwrap_or(str_to_int(a), 200000) end), 0, 200000)
  let o = new_game(42, 0, 0, 0, n)
  println(str_cat("games ", show(o.games), " total ", show(o.total), " checksum ", show(o.sum)))
end
