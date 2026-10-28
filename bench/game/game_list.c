/* game.c with GPLM's data structures: the body is an immutable-style array that is copied on every
   move (list_cons + list_slice) and searched linearly (list_contains). Same output as game.c. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
enum { W = 32, H = 24 };
typedef struct { int x, y; } P;
static P *body; static int len; static long rng = 42; static int dir, score; static P food;
static long next(long r) { return (r * 1103515245L + 12345L) % 2147483648L; }
static int contains(const P *b, int n, P p) { for (int i = 0; i < n; i++) if (b[i].x == p.x && b[i].y == p.y) return 1; return 0; }
static void place(void) { for (;;) { rng = next(rng); int x = rng % W; rng = next(rng); int y = rng % H; P f = {x, y}; if (!contains(body, len, f)) { food = f; return; } } }
static void new_game(void) { free(body); body = malloc(sizeof(P) * 3); len = 3; dir = 1; score = 0;
  for (int i = 0; i < 3; i++) body[i] = (P){16 - i, 12}; place(); }
static P step(P p, int d) { if (d == 0) p.y--; else if (d == 1) p.x++; else if (d == 2) p.y++; else p.x--; return p; }
static int is_free(P p) { return p.x >= 0 && p.x < W && p.y >= 0 && p.y < H && !contains(body, len - 1, p); }
int main(int argc, char **argv) {
  long n = argc > 1 ? atol(argv[1]) : 200000, games = 0, total = 0, sum = 0;
  new_game();
  for (long i = 0; i < n; i++) {
    P h = body[0]; int c[6], k = 0;
    if (food.x > h.x) c[k++] = 1; else if (food.x < h.x) c[k++] = 3;
    if (food.y > h.y) c[k++] = 2; else if (food.y < h.y) c[k++] = 0;
    for (int d = 0; d < 4; d++) c[k++] = d;
    int d = dir;
    for (int j = 0; j < k; j++) if (c[j] != (dir + 2) % 4 && is_free(step(h, c[j]))) { d = c[j]; break; }
    P nh = step(h, d);
    if (!is_free(nh)) { games++; total += score; new_game(); sum = (sum * 31 + body[0].x * 32 + body[0].y) % 1000000007; continue; }
    int grow = nh.x == food.x && nh.y == food.y, nl = grow ? len + 1 : len;
    P *nb = malloc(sizeof(P) * nl); nb[0] = nh; memcpy(nb + 1, body, sizeof(P) * (nl - 1));
    free(body); body = nb; len = nl; dir = d;
    if (grow) { score++; place(); }
    sum = (sum * 31 + nh.x * 32 + nh.y) % 1000000007;
  }
  printf("games %ld total %ld checksum %ld\n", games, total + score, sum);
  return 0;
}
