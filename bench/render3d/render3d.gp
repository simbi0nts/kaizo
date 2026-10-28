type V = { x: Int, y: Int, z: Int } end
type Tri = { a: V, b: V, c: V, color: Int, depth: Int, ord: Int } end
type Seg = { x0: Int, x1: Int, c: Int } end

let sines = [0, 101, 201, 301, 401, 501, 601, 700, 799, 897, 995, 1092, 1189, 1285, 1380, 1474, 1567, 1660, 1751, 1842, 1931, 2019, 2106, 2191, 2276, 2359, 2440, 2520, 2598, 2675, 2751, 2824, 2896, 2967, 3035, 3102, 3166, 3229, 3290, 3349, 3406, 3461, 3513, 3564, 3612, 3659, 3703, 3745, 3784, 3822, 3857, 3889, 3920, 3948, 3973, 3996, 4017, 4036, 4052, 4065, 4076, 4085, 4091, 4095, 4096, 4095, 4091, 4085, 4076, 4065, 4052, 4036, 4017, 3996, 3973, 3948, 3920, 3889, 3857, 3822, 3784, 3745, 3703, 3659, 3612, 3564, 3513, 3461, 3406, 3349, 3290, 3229, 3166, 3102, 3035, 2967, 2896, 2824, 2751, 2675, 2598, 2520, 2440, 2359, 2276, 2191, 2106, 2019, 1931, 1842, 1751, 1660, 1567, 1474, 1380, 1285, 1189, 1092, 995, 897, 799, 700, 601, 501, 401, 301, 201, 101, 0, -101, -201, -301, -401, -501, -601, -700, -799, -897, -995, -1092, -1189, -1285, -1380, -1474, -1567, -1660, -1751, -1842, -1931, -2019, -2106, -2191, -2276, -2359, -2440, -2520, -2598, -2675, -2751, -2824, -2896, -2967, -3035, -3102, -3166, -3229, -3290, -3349, -3406, -3461, -3513, -3564, -3612, -3659, -3703, -3745, -3784, -3822, -3857, -3889, -3920, -3948, -3973, -3996, -4017, -4036, -4052, -4065, -4076, -4085, -4091, -4095, -4096, -4095, -4091, -4085, -4076, -4065, -4052, -4036, -4017, -3996, -3973, -3948, -3920, -3889, -3857, -3822, -3784, -3745, -3703, -3659, -3612, -3564, -3513, -3461, -3406, -3349, -3290, -3229, -3166, -3102, -3035, -2967, -2896, -2824, -2751, -2675, -2598, -2520, -2440, -2359, -2276, -2191, -2106, -2019, -1931, -1842, -1751, -1660, -1567, -1474, -1380, -1285, -1189, -1092, -995, -897, -799, -700, -601, -501, -401, -301, -201, -101]
let tris = [[0, 1, 2], [0, 2, 3], [5, 4, 7], [5, 7, 6], [4, 0, 3], [4, 3, 7], [1, 5, 6], [1, 6, 2], [3, 2, 6], [3, 6, 7], [4, 5, 1], [4, 1, 0]]
let facecol = [0xE04040, 0x40E040, 0x4040E0, 0xE0E040, 0x40E0E0, 0xE040E0]
let cube = [V { x: -100, y: -100, z: -100 }, V { x: 100, y: -100, z: -100 }, V { x: 100, y: 100, z: -100 }, V { x: -100, y: 100, z: -100 },
  V { x: -100, y: -100, z: 100 }, V { x: 100, y: -100, z: 100 }, V { x: 100, y: 100, z: 100 }, V { x: -100, y: 100, z: 100 }]

fn sin(a: Int) -> Int
  unwrap_or(list_get(sines, a % 256), 0)
end

fn cos(a: Int) -> Int
  sin(a + 64)
end

# world position (x, y, z) and its projection kept together: x/y = screen, z = depth
fn transform(p: V, ox: Int, ax: Int, ay: Int) -> V
  let x1 = (p.x * cos(ay) + p.z * sin(ay)) / 4096
  let z1 = (p.z * cos(ay) - p.x * sin(ay)) / 4096
  let y2 = (p.y * cos(ax) - z1 * sin(ax)) / 4096
  let z2 = (p.y * sin(ax) + z1 * cos(ax)) / 4096
  let wx = x1 + ox
  let wz = z2 + 700
  V { x: 160 + wx * 256 / wz, y: 120 - y2 * 256 / wz, z: wz }
end

fn shade(c: Int, s: Int) -> Int
  let r = bit_and(bit_shr(c, 16), 255) * s / 256
  let g = bit_and(bit_shr(c, 8), 255) * s / 256
  let b = bit_and(c, 255) * s / 256
  bit_or(bit_shl(r, 16), bit_shl(g, 8), b)
end

fn clamp(v: Int, lo: Int, hi: Int) -> Int
  if v < lo then lo elif v > hi then hi else v end
end

fn cube_tris(t: Int, i: Int) -> List[Tri]
  let vs = list_map(cube, fn(p) transform(p, -240 + 160 * i, 2 * t + 17 * i, 3 * t + 40 * i) end)
  let idx = list_range(0, 12)
  let all = list_map(idx, fn(k)
    let ix = unwrap_or(list_get(tris, k), [0, 0, 0])
    let a = unwrap_or(list_get(vs, unwrap_or(list_get(ix, 0), 0)), V { x: 0, y: 0, z: 1 })
    let b = unwrap_or(list_get(vs, unwrap_or(list_get(ix, 1), 0)), V { x: 0, y: 0, z: 1 })
    let c = unwrap_or(list_get(vs, unwrap_or(list_get(ix, 2), 0)), V { x: 0, y: 0, z: 1 })
    let depth = a.z + b.z + c.z
    let col = shade(unwrap_or(list_get(facecol, k / 2), 0), clamp(512 - depth / 8, 64, 256))
    Tri { a: a, b: b, c: c, color: col, depth: depth, ord: i * 12 + k }
  end)
  list_filter(all, fn(tr) (tr.b.x - tr.a.x) * (tr.c.y - tr.a.y) - (tr.b.y - tr.a.y) * (tr.c.x - tr.a.x) < 0 end)
end

fn edge(p: V, q: V, y: Int, acc: List[Int]) -> List[Int]
  if p.y == q.y then acc
  elif y >= min(p.y, q.y) && y <= max(p.y, q.y) then list_cons(p.x + (y - p.y) * (q.x - p.x) / (q.y - p.y), acc)
  else acc end
end

fn span(tr: Tri, y: Int) -> Option[Seg]
  let xs = edge(tr.a, tr.b, y, edge(tr.b, tr.c, y, edge(tr.c, tr.a, y, [])))
  match xs
    case [] -> None
    case [x, ..rest] ->
      let lo = list_fold(rest, x, fn(m, v) min(m, v) end)
      let hi = list_fold(rest, x, fn(m, v) max(m, v) end)
      let x0 = max(0, lo)
      let x1 = min(319, hi)
      if x0 > x1 then None else Some(Seg { x0: x0, x1: x1, c: tr.color }) end
  end
end

# segs: front-most first; the colour of x is the first segment covering it
fn pixel(segs: List[Seg], x: Int) -> Int
  match segs
    case [] -> 0
    case [s, ..rest] -> if x >= s.x0 && x <= s.x1 then s.c else pixel(rest, x) end
  end
end

fn row_sum(segs: List[Seg], y: Int, x: Int, acc: Int) -> Int
  if x == 320 then acc
  else row_sum(segs, y, x + 1, (acc + pixel(segs, x) * (x + 1 + y)) % 1000000007) end
end

fn frame(t: Int) -> Int
  let all = list_concat(list_concat(cube_tris(t, 0), cube_tris(t, 1)), list_concat(cube_tris(t, 2), cube_tris(t, 3)))
  # front-most first: nearest depth first; ties: later triangle first (it is drawn last)
  let front = list_sort_by(all, fn(p, q) p.depth < q.depth || (p.depth == q.depth && p.ord > q.ord) end)
  list_fold(list_range(0, 240), 0, fn(acc, y)
    let segs = list_fold(list_reverse(front), [], fn(ss, tr)
      match span(tr, y)
        case Some(s) -> list_cons(s, ss)
        case None -> ss
      end
    end)
    if eq(list_len(segs), 0) then acc else (acc + row_sum(segs, y, 0, 0)) % 1000000007 end
  end)
end

fn run(t: Int, n: Int, total: Int) -> Int
  if t == n then total else run(t + 1, n, (total * 7 + frame(t)) % 1000000007) end
end

fn main() -> Unit ! [io]
  let n = unwrap_or(str_to_int(unwrap_or(list_get(args(), 0), "120")), 120)
  println(str_cat("checksum ", show(run(0, n, 0))))
end
