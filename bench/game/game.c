#include <stdio.h>
#include <stdlib.h>
#include <string.h>
enum { W = 32, H = 24, CAP = W * H + 1 };
typedef struct { int x, y; } P;
static P body[CAP]; static int head_i, len; static unsigned char occ[W][H];
static long rng = 42; static int dir, score; static P food;
static long next(long r) { return (r * 1103515245L + 12345L) % 2147483648L; }
static P at(int k) { return body[(head_i + k) % CAP]; }          /* k = 0 is the head */
static void place(void) {
  for (;;) { rng = next(rng); int x = rng % W; rng = next(rng); int y = rng % H;
    if (!occ[x][y]) { food.x = x; food.y = y; return; } }
}
static void new_game(void) {
  memset(occ, 0, sizeof occ); head_i = 0; len = 3; dir = 1; score = 0;
  for (int i = 0; i < 3; i++) { body[i] = (P){16 - i, 12}; occ[16 - i][12] = 1; }
  place();
}
static P step(P p, int d) {
  if (d == 0) p.y--; else if (d == 1) p.x++; else if (d == 2) p.y++; else p.x--; return p;
}
static int is_free(P p) {                 /* inside and not on the body without its last segment */
  if (p.x < 0 || p.x >= W || p.y < 0 || p.y >= H) return 0;
  P t = at(len - 1);
  if (p.x == t.x && p.y == t.y) return 1;
  return !occ[p.x][p.y];
}
int main(int argc, char **argv) {
  long n = argc > 1 ? atol(argv[1]) : 200000, games = 0, total = 0, sum = 0;
  new_game();
  for (long i = 0; i < n; i++) {
    P h = at(0); int c[6], k = 0;
    if (food.x > h.x) c[k++] = 1; else if (food.x < h.x) c[k++] = 3;
    if (food.y > h.y) c[k++] = 2; else if (food.y < h.y) c[k++] = 0;
    for (int d = 0; d < 4; d++) c[k++] = d;
    int d = dir;
    for (int j = 0; j < k; j++) if (c[j] != (dir + 2) % 4 && is_free(step(h, c[j]))) { d = c[j]; break; }
    P nh = step(h, d);
    if (!is_free(nh)) { games++; total += score; new_game(); P g = at(0); sum = (sum * 31 + g.x * 32 + g.y) % 1000000007; continue; }
    if (nh.x == food.x && nh.y == food.y) {
      head_i = (head_i + CAP - 1) % CAP; body[head_i] = nh; len++; occ[nh.x][nh.y] = 1; score++; dir = d; place();
    } else {
      P t = at(len - 1); occ[t.x][t.y] = 0;
      head_i = (head_i + CAP - 1) % CAP; body[head_i] = nh; occ[nh.x][nh.y] = 1; dir = d;
    }
    sum = (sum * 31 + nh.x * 32 + nh.y) % 1000000007;
  }
  printf("games %ld total %ld checksum %ld\n", games, total + score, sum);
  return 0;
}
