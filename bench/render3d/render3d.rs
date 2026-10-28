const W: usize = 320;
const H: usize = 240;
const SINES: [i64; 256] = [0, 101, 201, 301, 401, 501, 601, 700, 799, 897, 995, 1092, 1189, 1285, 1380, 1474, 1567, 1660, 1751, 1842, 1931, 2019, 2106, 2191, 2276, 2359, 2440, 2520, 2598, 2675, 2751, 2824, 2896, 2967, 3035, 3102, 3166, 3229, 3290, 3349, 3406, 3461, 3513, 3564, 3612, 3659, 3703, 3745, 3784, 3822, 3857, 3889, 3920, 3948, 3973, 3996, 4017, 4036, 4052, 4065, 4076, 4085, 4091, 4095, 4096, 4095, 4091, 4085, 4076, 4065, 4052, 4036, 4017, 3996, 3973, 3948, 3920, 3889, 3857, 3822, 3784, 3745, 3703, 3659, 3612, 3564, 3513, 3461, 3406, 3349, 3290, 3229, 3166, 3102, 3035, 2967, 2896, 2824, 2751, 2675, 2598, 2520, 2440, 2359, 2276, 2191, 2106, 2019, 1931, 1842, 1751, 1660, 1567, 1474, 1380, 1285, 1189, 1092, 995, 897, 799, 700, 601, 501, 401, 301, 201, 101, 0, -101, -201, -301, -401, -501, -601, -700, -799, -897, -995, -1092, -1189, -1285, -1380, -1474, -1567, -1660, -1751, -1842, -1931, -2019, -2106, -2191, -2276, -2359, -2440, -2520, -2598, -2675, -2751, -2824, -2896, -2967, -3035, -3102, -3166, -3229, -3290, -3349, -3406, -3461, -3513, -3564, -3612, -3659, -3703, -3745, -3784, -3822, -3857, -3889, -3920, -3948, -3973, -3996, -4017, -4036, -4052, -4065, -4076, -4085, -4091, -4095, -4096, -4095, -4091, -4085, -4076, -4065, -4052, -4036, -4017, -3996, -3973, -3948, -3920, -3889, -3857, -3822, -3784, -3745, -3703, -3659, -3612, -3564, -3513, -3461, -3406, -3349, -3290, -3229, -3166, -3102, -3035, -2967, -2896, -2824, -2751, -2675, -2598, -2520, -2440, -2359, -2276, -2191, -2106, -2019, -1931, -1842, -1751, -1660, -1567, -1474, -1380, -1285, -1189, -1092, -995, -897, -799, -700, -601, -501, -401, -301, -201, -101];
const TRIS: [[usize; 3]; 12] = [[0,1,2],[0,2,3],[5,4,7],[5,7,6],[4,0,3],[4,3,7],[1,5,6],[1,6,2],[3,2,6],[3,6,7],[4,5,1],[4,1,0]];
const FACECOL: [i64; 6] = [0xE04040, 0x40E040, 0x4040E0, 0xE0E040, 0x40E0E0, 0xE040E0];
const CUBE: [[i64; 3]; 8] = [[-100,-100,-100],[100,-100,-100],[100,100,-100],[-100,100,-100],[-100,-100,100],[100,-100,100],[100,100,100],[-100,100,100]];
#[derive(Clone, Copy)]
struct V { x: i64, y: i64, z: i64 }
struct Tri { p: [V; 3], color: u32, depth: i64, ord: usize }
fn fdiv(a: i64, b: i64) -> i64 { let q = a / b; if a % b != 0 && ((a < 0) != (b < 0)) { q - 1 } else { q } }
fn sn(a: i64) -> i64 { SINES[a.rem_euclid(256) as usize] }
fn cs(a: i64) -> i64 { sn(a + 64) }
fn main() {
    let n: i64 = std::env::args().nth(1).and_then(|s| s.parse().ok()).unwrap_or(120);
    let mut pix = vec![0u32; W * H];
    let mut total: i64 = 0;
    for t in 0..n {
        let mut tris: Vec<Tri> = Vec::with_capacity(48);
        for i in 0..4i64 {
            let (ox, ax, ay) = (-240 + 160 * i, 2 * t + 17 * i, 3 * t + 40 * i);
            let vs: Vec<V> = CUBE.iter().map(|&[x, y, z]| {
                let x1 = fdiv(x * cs(ay) + z * sn(ay), 4096);
                let z1 = fdiv(z * cs(ay) - x * sn(ay), 4096);
                let y2 = fdiv(y * cs(ax) - z1 * sn(ax), 4096);
                let z2 = fdiv(y * sn(ax) + z1 * cs(ax), 4096);
                let (wx, wz) = (x1 + ox, z2 + 700);
                V { x: 160 + fdiv(wx * 256, wz), y: 120 - fdiv(y2 * 256, wz), z: wz }
            }).collect();
            for (m, ix) in TRIS.iter().enumerate() {
                let (a, b, c) = (vs[ix[0]], vs[ix[1]], vs[ix[2]]);
                if (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) >= 0 { continue; }
                let depth = a.z + b.z + c.z;
                let s = (512 - fdiv(depth, 8)).clamp(64, 256);
                let col = FACECOL[m / 2];
                let ch = |sh: i64| fdiv(((col >> sh) & 255) * s, 256) << sh;
                tris.push(Tri { p: [a, b, c], color: (ch(16) | ch(8) | ch(0)) as u32, depth, ord: i as usize * 12 + m });
            }
        }
        tris.sort_by(|p, q| q.depth.cmp(&p.depth).then(p.ord.cmp(&q.ord)));
        pix.iter_mut().for_each(|p| *p = 0);
        for tr in &tris {
            let ymin = tr.p.iter().map(|v| v.y).min().unwrap().max(0);
            let ymax = tr.p.iter().map(|v| v.y).max().unwrap().min(H as i64 - 1);
            for y in ymin..=ymax {
                let mut span: Option<(i64, i64)> = None;
                for (p, q) in [(tr.p[0], tr.p[1]), (tr.p[1], tr.p[2]), (tr.p[2], tr.p[0])] {
                    if p.y == q.y || y < p.y.min(q.y) || y > p.y.max(q.y) { continue; }
                    let x = p.x + fdiv((y - p.y) * (q.x - p.x), q.y - p.y);
                    span = Some(match span { None => (x, x), Some((l, h)) => (l.min(x), h.max(x)) });
                }
                if let Some((l, h)) = span {
                    let row = y as usize * W;
                    for x in l.max(0)..=h.min(W as i64 - 1) { pix[row + x as usize] = tr.color; }
                }
            }
        }
        let mut f: i64 = 0;
        for y in 0..H { for x in 0..W { f = (f + pix[y * W + x] as i64 * (x + 1 + y) as i64) % 1000000007; } }
        total = (total * 7 + f) % 1000000007;
    }
    println!("checksum {}", total);
}
