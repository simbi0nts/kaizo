use std::collections::VecDeque;
const W: i32 = 32;
const H: i32 = 24;
#[derive(Clone, Copy, PartialEq)]
struct P { x: i32, y: i32 }
struct Game { body: VecDeque<P>, occ: Vec<bool>, dir: i32, food: P, score: i64, rng: i64 }
fn next(r: i64) -> i64 { (r * 1103515245 + 12345) % 2147483648 }
fn step(p: P, d: i32) -> P {
    match d { 0 => P { x: p.x, y: p.y - 1 }, 1 => P { x: p.x + 1, y: p.y }, 2 => P { x: p.x, y: p.y + 1 }, _ => P { x: p.x - 1, y: p.y } }
}
impl Game {
    fn new(rng: i64) -> Game {
        let mut g = Game { body: VecDeque::new(), occ: vec![false; (W * H) as usize], dir: 1, food: P { x: 0, y: 0 }, score: 0, rng };
        for i in 0..3 { let p = P { x: 16 - i, y: 12 }; g.body.push_back(p); g.occ[(p.x * H + p.y) as usize] = true; }
        g.place();
        g
    }
    fn place(&mut self) {
        loop {
            self.rng = next(self.rng); let x = (self.rng % W as i64) as i32;
            self.rng = next(self.rng); let y = (self.rng % H as i64) as i32;
            if !self.occ[(x * H + y) as usize] { self.food = P { x, y }; return; }
        }
    }
    fn free(&self, p: P) -> bool {
        if p.x < 0 || p.x >= W || p.y < 0 || p.y >= H { return false; }
        if *self.body.back().unwrap() == p { return true; }
        !self.occ[(p.x * H + p.y) as usize]
    }
}
fn main() {
    let n: i64 = std::env::args().nth(1).and_then(|s| s.parse().ok()).unwrap_or(200000);
    let (mut games, mut total, mut sum) = (0i64, 0i64, 0i64);
    let mut g = Game::new(42);
    for _ in 0..n {
        let h = g.body[0];
        let mut c = Vec::with_capacity(6);
        if g.food.x > h.x { c.push(1) } else if g.food.x < h.x { c.push(3) }
        if g.food.y > h.y { c.push(2) } else if g.food.y < h.y { c.push(0) }
        c.extend_from_slice(&[0, 1, 2, 3]);
        let d = c.iter().copied().find(|&d| d != (g.dir + 2) % 4 && g.free(step(h, d))).unwrap_or(g.dir);
        let nh = step(h, d);
        if !g.free(nh) {
            games += 1; total += g.score; g = Game::new(g.rng);
            let s = g.body[0]; sum = (sum * 31 + (s.x * 32 + s.y) as i64) % 1000000007; continue;
        }
        if nh == g.food {
            g.body.push_front(nh); g.occ[(nh.x * H + nh.y) as usize] = true; g.score += 1; g.dir = d; g.place();
        } else {
            let t = g.body.pop_back().unwrap(); g.occ[(t.x * H + t.y) as usize] = false;
            g.body.push_front(nh); g.occ[(nh.x * H + nh.y) as usize] = true; g.dir = d;
        }
        sum = (sum * 31 + (nh.x * 32 + nh.y) as i64) % 1000000007;
    }
    println!("games {} total {} checksum {}", games, total + g.score, sum);
}
