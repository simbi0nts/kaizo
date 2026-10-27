# 3D demo scene: a software renderer in integer (fixed-point) math, shown through X11.
# Flat-shaded convex solids (back-face culling, depth-sorted), infinite checker floor with fog,
# sky gradient. Rows are built from colour spans, so the cost grows with rows, not pixels.
# Run: kaizo run apps/demo3d/main.gp      q / Esc quits

import x11

let w = 640
let h = 400
let cx = 320
let horizon = 150
let focal = 360
let floor_y = -300

type V3 = { x: Int, y: Int, z: Int } end
type P2 = { x: Int, y: Int } end
type Face = { idx: List[Int], color: Int } end
type Mesh = { verts: List[V3], faces: List[Face] } end
type Poly = { pts: List[P2], color: Int, depth: Int, ymin: Int, ymax: Int } end
type Seg = { x0: Int, x1: Int, c: Int } end

# ---------- fixed-point trigonometry: sin(2*pi*i/256) * 4096 ----------

let sines = [0, 101, 201, 301, 401, 501, 601, 700, 799, 897, 995, 1092, 1189, 1285, 1380, 1474, 1567, 1660, 1751, 1842, 1931, 2019, 2106, 2191, 2276, 2359, 2440, 2520, 2598, 2675, 2751, 2824, 2896, 2967, 3035, 3102, 3166, 3229, 3290, 3349, 3406, 3461, 3513, 3564, 3612, 3659, 3703, 3745, 3784, 3822, 3857, 3889, 3920, 3948, 3973, 3996, 4017, 4036, 4052, 4065, 4076, 4085, 4091, 4095, 4096, 4095, 4091, 4085, 4076, 4065, 4052, 4036, 4017, 3996, 3973, 3948, 3920, 3889, 3857, 3822, 3784, 3745, 3703, 3659, 3612, 3564, 3513, 3461, 3406, 3349, 3290, 3229, 3166, 3102, 3035, 2967, 2896, 2824, 2751, 2675, 2598, 2520, 2440, 2359, 2276, 2191, 2106, 2019, 1931, 1842, 1751, 1660, 1567, 1474, 1380, 1285, 1189, 1092, 995, 897, 799, 700, 601, 501, 401, 301, 201, 101, 0, -101, -201, -301, -401, -501, -601, -700, -799, -897, -995, -1092, -1189, -1285, -1380, -1474, -1567, -1660, -1751, -1842, -1931, -2019, -2106, -2191, -2276, -2359, -2440, -2520, -2598, -2675, -2751, -2824, -2896, -2967, -3035, -3102, -3166, -3229, -3290, -3349, -3406, -3461, -3513, -3564, -3612, -3659, -3703, -3745, -3784, -3822, -3857, -3889, -3920, -3948, -3973, -3996, -4017, -4036, -4052, -4065, -4076, -4085, -4091, -4095, -4096, -4095, -4091, -4085, -4076, -4065, -4052, -4036, -4017, -3996, -3973, -3948, -3920, -3889, -3857, -3822, -3784, -3745, -3703, -3659, -3612, -3564, -3513, -3461, -3406, -3349, -3290, -3229, -3166, -3102, -3035, -2967, -2896, -2824, -2751, -2675, -2598, -2520, -2440, -2359, -2276, -2191, -2106, -2019, -1931, -1842, -1751, -1660, -1567, -1474, -1380, -1285, -1189, -1092, -995, -897, -799, -700, -601, -501, -401, -301, -201, -101]

fn sin(a: Int) -> Int
  unwrap_or(list_get(sines, mod(a, 256)), 0)
end

fn cos(a: Int) -> Int
  sin(add(a, 64))
end

fn isqrt(n: Int) -> Int
  if le(n, 1) then n else isqrt_step(n, n) end
end

fn isqrt_step(n: Int, x: Int) -> Int
  let y = div(add(x, div(n, x)), 2)
  if ge(y, x) then x else isqrt_step(n, y) end
end

# ---------- meshes ----------

fn v(x: Int, y: Int, z: Int) -> V3
  V3 { x: x, y: y, z: z }
end

fn cube(colors: List[Int]) -> Mesh
  let c = fn(i) unwrap_or(list_get(colors, mod(i, list_len(colors))), 0xFFFFFF) end
  Mesh { verts: [v(-1, -1, -1), v(1, -1, -1), v(1, 1, -1), v(-1, 1, -1), v(-1, -1, 1), v(1, -1, 1), v(1, 1, 1), v(-1, 1, 1)],
    faces: [Face { idx: [0, 1, 2, 3], color: c(0) }, Face { idx: [5, 4, 7, 6], color: c(1) }, Face { idx: [4, 0, 3, 7], color: c(2) },
      Face { idx: [1, 5, 6, 2], color: c(3) }, Face { idx: [3, 2, 6, 7], color: c(4) }, Face { idx: [4, 5, 1, 0], color: c(5) }] }
end

fn octahedron(a: Int, b: Int) -> Mesh
  Mesh { verts: [v(1, 0, 0), v(-1, 0, 0), v(0, 1, 0), v(0, -1, 0), v(0, 0, 1), v(0, 0, -1)],
    faces: [Face { idx: [0, 2, 4], color: a }, Face { idx: [4, 2, 1], color: b }, Face { idx: [1, 2, 5], color: a }, Face { idx: [5, 2, 0], color: b },
      Face { idx: [4, 3, 0], color: b }, Face { idx: [1, 3, 4], color: a }, Face { idx: [5, 3, 1], color: b }, Face { idx: [0, 3, 5], color: a }] }
end

# ---------- transform, light, project ----------

fn rotate(p: V3, ax: Int, ay: Int) -> V3
  let x1 = div(add(mul(p.x, cos(ay)), mul(p.z, sin(ay))), 4096)
  let z1 = div(sub(mul(p.z, cos(ay)), mul(p.x, sin(ay))), 4096)
  V3 { x: x1, y: div(sub(mul(p.y, cos(ax)), mul(z1, sin(ax))), 4096), z: div(add(mul(p.y, sin(ax)), mul(z1, cos(ax))), 4096) }
end

fn project(p: V3) -> P2
  P2 { x: add(cx, div(mul(p.x, focal), p.z)), y: sub(horizon, div(mul(p.y, focal), p.z)) }
end

fn shade(c: Int, b: Int) -> Int
  let ch = fn(sh) bit_shl(min(255, div(mul(bit_and(bit_shr(c, sh), 255), b), 1024)), sh) end
  bit_or(bit_or(ch(16), ch(8)), ch(0))
end

# light direction (normalised, *1024): from upper left, towards the scene
let light = V3 { x: -443, y: 739, z: -512 }

fn sum3(vs: List[V3]) -> V3
  list_fold(vs, v(0, 0, 0), fn(a, p) V3 { x: add(a.x, p.x), y: add(a.y, p.y), z: add(a.z, p.z) } end)
end

fn pick(vs: List[V3], idx: List[Int]) -> List[V3]
  list_map(idx, fn(i) unwrap_or(list_get(vs, i), v(0, 0, 1)) end)
end

# the visible, lit faces of a mesh scaled by size, rotated, moved to pos (camera space)
fn place(m: Mesh, size: Int, ax: Int, ay: Int, pos: V3) -> List[Poly]
  let verts = list_map(m.verts, fn(p)
    let r = rotate(V3 { x: mul(p.x, size), y: mul(p.y, size), z: mul(p.z, size) }, ax, ay)
    V3 { x: add(r.x, pos.x), y: add(r.y, pos.y), z: add(r.z, pos.z) }
  end)
  list_fold(m.faces, [], fn(acc, f)
    let fv = pick(verts, f.idx)
    let n = list_len(fv)
    let s = sum3(fv)
    let center = V3 { x: div(s.x, n), y: div(s.y, n), z: div(s.z, n) }
    let nrm = V3 { x: sub(center.x, pos.x), y: sub(center.y, pos.y), z: sub(center.z, pos.z) }
    if ge(add(add(mul(nrm.x, center.x), mul(nrm.y, center.y)), mul(nrm.z, center.z)), 0) then acc else
      let len = max(1, isqrt(add(add(mul(nrm.x, nrm.x), mul(nrm.y, nrm.y)), mul(nrm.z, nrm.z))))
      let d = div(add(add(mul(nrm.x, light.x), mul(nrm.y, light.y)), mul(nrm.z, light.z)), len)
      let pts = list_map(fv, project)
      let ys = list_map(pts, fn(p) p.y end)
      list_push(acc, Poly { pts: pts, color: shade(f.color, add(330, div(mul(max(0, d), 760), 1024))), depth: center.z,
        ymin: list_fold(ys, h, min), ymax: list_fold(ys, 0, max) })
    end
  end)
end

# ---------- rows ----------

# horizontal extent of a convex polygon on row y (half-open [x0, x1)), clipped to the screen
fn span_at(p: Poly, y: Int) -> Option[Seg]
  let n = list_len(p.pts)
  let xs = list_fold(list_range(0, n), [], fn(acc, i)
    let a = unwrap_or(list_get(p.pts, i), P2 { x: 0, y: 0 })
    let b = unwrap_or(list_get(p.pts, mod(add(i, 1), n)), P2 { x: 0, y: 0 })
    if and(ne(a.y, b.y), and(ge(y, min(a.y, b.y)), lt(y, max(a.y, b.y)))) then
      list_push(acc, add(a.x, div(mul(sub(y, a.y), sub(b.x, a.x)), sub(b.y, a.y))))
    else acc end
  end)
  match xs
    case [] -> None
    case [_] -> None
    case _ ->
      let x0 = max(0, list_fold(xs, w, min))
      let x1 = min(w, list_fold(xs, 0, max))
      if lt(x0, x1) then Some(Seg { x0: x0, x1: x1, c: p.color }) else None end
  end
end

# paint s over sorted, non-overlapping segments
fn overlay(segs: List[Seg], s: Seg) -> List[Seg]
  let left = list_fold(segs, [], fn(acc, g) if lt(g.x0, s.x0) then list_push(acc, { g with x1: min(g.x1, s.x0) }) else acc end end)
  let right = list_fold(segs, [], fn(acc, g) if gt(g.x1, s.x1) then list_push(acc, { g with x0: max(g.x0, s.x1) }) else acc end end)
  list_concat(list_push(left, s), right)
end

fn mix(a: Int, b: Int, t: Int) -> Int
  let ch = fn(sh) bit_shl(div(add(mul(bit_and(bit_shr(a, sh), 255), sub(256, t)), mul(bit_and(bit_shr(b, sh), 255), t)), 256), sh) end
  bit_or(bit_or(ch(16), ch(8)), ch(0))
end

let fog = 0x9DB4D0

fn sky(y: Int) -> List[Seg]
  [Seg { x0: 0, x1: w, c: mix(0x1B2A4A, fog, div(mul(y, 256), horizon)) }]
end

# checker floor row: depth from the row, tiles every 200 units, scrolling with time
fn floor_row(y: Int, scroll: Int) -> List[Seg]
  let z = div(mul(focal, sub(0, floor_y)), max(1, sub(y, horizon)))
  let t = min(256, div(mul(z, 256), 9000))
  let tile = div(mul(200, focal), z)
  let row_k = div(add(z, scroll), 200)
  if lt(tile, 6) then [Seg { x0: 0, x1: w, c: mix(0x6A7A8E, fog, t) }] else
    let k0 = div(mul(sub(0, cx), z), mul(focal, 200))
    let k1 = div(mul(sub(w, cx), z), mul(focal, 200))
    list_map(list_range(k0, add(k1, 1)), fn(k)
      let a = max(0, add(cx, div(mul(mul(k, 200), focal), z)))
      let b = min(w, add(cx, div(mul(mul(add(k, 1), 200), focal), z)))
      let base = if eq(mod(add(k, row_k), 2), 0) then 0xE8ECF2 else 0x3A4A5E end
      Seg { x0: a, x1: b, c: mix(base, fog, t) }
    end)
  end
end

fn row_string(segs: List[Seg]) -> String
  str_join(list_map(list_filter(segs, fn(s) lt(s.x0, s.x1) end), fn(s) str_repeat(x11.pixel(s.c), sub(s.x1, s.x0)) end), "")
end

fn by_depth(polys: List[Poly]) -> List[Poly]
  # far first (painter's algorithm); few polygons, insertion sort is fine
  list_fold(polys, [], fn(acc, p) insert(acc, p) end)
end

fn insert(sorted: List[Poly], p: Poly) -> List[Poly]
  match sorted
    case [] -> [p]
    case [q, ..rest] -> if gt(p.depth, q.depth) then list_cons(p, sorted) else list_cons(q, insert(rest, p)) end
  end
end

# ---------- the scene at time t (ms) ----------

fn scene(t: Int) -> List[Poly]
  let a = div(t, 24)
  let orbit = div(t, 40)
  let big = place(cube([0xE5484D, 0xF76B15, 0xFFC53D, 0x46A758, 0x0090FF, 0x8E4EC6]), 130, a, mul(a, 2), v(0, add(-40, div(mul(sin(div(t, 12)), 40), 4096)), 1150))
  let oct = place(octahedron(0x12A594, 0xD6409F), 110, div(a, 2), mul(a, 3), v(div(mul(cos(orbit), 480), 4096), 40, add(1150, div(mul(sin(orbit), 480), 4096))))
  let s1 = place(cube([0xEDEEF0, 0xB0B4BA]), 45, mul(a, 3), a, v(div(mul(cos(add(orbit, 128)), 330), 4096), add(120, div(mul(sin(div(t, 9)), 60), 4096)), add(1150, div(mul(sin(add(orbit, 128)), 330), 4096))))
  let s2 = place(cube([0xFFC53D, 0x0090FF]), 35, a, mul(a, 3), v(div(mul(cos(add(orbit, 64)), 260), 4096), -150, add(1150, div(mul(sin(add(orbit, 64)), 260), 4096))))
  by_depth(list_concat(list_concat(big, oct), list_concat(s1, s2)))
end

fn render(t: Int) -> String
  let polys = scene(t)
  let scroll = div(mul(t, 3), 5)
  str_join(list_map(list_range(0, h), fn(y)
    let base = if le(y, horizon) then sky(y) else floor_row(y, scroll) end
    let segs = list_fold(polys, base, fn(acc, p)
      if and(ge(y, p.ymin), lt(y, p.ymax)) then
        match span_at(p, y)
          case Some(s) -> overlay(acc, s)
          case None -> acc
        end
      else acc end
    end)
    row_string(segs)
  end), "")
end

# ---------- main loop ----------

fn quit_requested(events: List[XEvent]) -> Bool
  list_fold(events, false, fn(acc, e)
    match e
      case XKey(k) -> or(acc, or(eq(k, "q"), eq(k, "esc")))
      case XClosed -> true
      case _ -> acc
    end
  end)
end

fn loop(x: X, start: Int, frames: Int, last_fps: Int, fps_at: Int) -> Int ! [net, time]
  let now = now_ms()
  let polled = x11.poll(x)
  if quit_requested(polled.events) then frames else
    let img = render(sub(now, start))
    let took = sub(now_ms(), now)
    let fresh = gt(sub(now, fps_at), 1000)
    let fps = if fresh then div(mul(frames, 1000), max(1, sub(now, start))) else last_fps end
    let label = str_join(["KAIZO 3D  -  software renderer in GPLM  -  ", show(fps), " fps (frame ", show(took), " ms)"], "")
    x11.send(polled.x, list_push(x11.image(polled.x.draw, 0, 0, w, h, img), x11.text(polled.x.draw, 0xFFFFFF, 10, 18, label)))
    sleep_ms(max(1, sub(33, sub(now_ms(), now))))
    loop(polled.x, start, add(frames, 1), fps, if fresh then now else fps_at end)
  end
end

fn main() -> Unit ! [io, fs, net, time]
  match x11.open()
    case Err(e) -> println(str_cat("cannot open the display: ", e))
    case Ok(x0) ->
      let x = x11.window(x0, w, h, "Kaizo 3D demo")
      let frames = loop(x, now_ms(), 0, 0, now_ms())
      x11.close(x)
      println(str_cat("frames rendered: ", show(frames)))
  end
end

test "fixed-point trig"
  expect_eq(sin(0), 0)
  expect_eq(sin(64), 4096)
  expect_eq(cos(0), 4096)
  expect_eq(isqrt(1000000), 1000)
end

test "rotation keeps length roughly"
  let r = rotate(v(1000, 0, 0), 32, 32)
  let len = isqrt(add(add(mul(r.x, r.x), mul(r.y, r.y)), mul(r.z, r.z)))
  expect(and(gt(len, 990), lt(len, 1010)), "length preserved")
end

test "overlay keeps segments sorted and covering"
  let segs = overlay([Seg { x0: 0, x1: 100, c: 1 }], Seg { x0: 20, x1: 30, c: 2 })
  expect_eq(list_map(segs, fn(s) [s.x0, s.x1, s.c] end), [[0, 20, 1], [20, 30, 2], [30, 100, 1]])
end

test "a frame is exactly w*h pixels"
  expect_eq(str_len(render(1234)), mul(mul(w, h), 4))
end
