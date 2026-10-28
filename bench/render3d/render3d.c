#include <stdio.h>
#include <stdlib.h>
enum { W = 320, H = 240 };
static const int SINES[256] = {0, 101, 201, 301, 401, 501, 601, 700, 799, 897, 995, 1092, 1189, 1285, 1380, 1474, 1567, 1660, 1751, 1842, 1931, 2019, 2106, 2191, 2276, 2359, 2440, 2520, 2598, 2675, 2751, 2824, 2896, 2967, 3035, 3102, 3166, 3229, 3290, 3349, 3406, 3461, 3513, 3564, 3612, 3659, 3703, 3745, 3784, 3822, 3857, 3889, 3920, 3948, 3973, 3996, 4017, 4036, 4052, 4065, 4076, 4085, 4091, 4095, 4096, 4095, 4091, 4085, 4076, 4065, 4052, 4036, 4017, 3996, 3973, 3948, 3920, 3889, 3857, 3822, 3784, 3745, 3703, 3659, 3612, 3564, 3513, 3461, 3406, 3349, 3290, 3229, 3166, 3102, 3035, 2967, 2896, 2824, 2751, 2675, 2598, 2520, 2440, 2359, 2276, 2191, 2106, 2019, 1931, 1842, 1751, 1660, 1567, 1474, 1380, 1285, 1189, 1092, 995, 897, 799, 700, 601, 501, 401, 301, 201, 101, 0, -101, -201, -301, -401, -501, -601, -700, -799, -897, -995, -1092, -1189, -1285, -1380, -1474, -1567, -1660, -1751, -1842, -1931, -2019, -2106, -2191, -2276, -2359, -2440, -2520, -2598, -2675, -2751, -2824, -2896, -2967, -3035, -3102, -3166, -3229, -3290, -3349, -3406, -3461, -3513, -3564, -3612, -3659, -3703, -3745, -3784, -3822, -3857, -3889, -3920, -3948, -3973, -3996, -4017, -4036, -4052, -4065, -4076, -4085, -4091, -4095, -4096, -4095, -4091, -4085, -4076, -4065, -4052, -4036, -4017, -3996, -3973, -3948, -3920, -3889, -3857, -3822, -3784, -3745, -3703, -3659, -3612, -3564, -3513, -3461, -3406, -3349, -3290, -3229, -3166, -3102, -3035, -2967, -2896, -2824, -2751, -2675, -2598, -2520, -2440, -2359, -2276, -2191, -2106, -2019, -1931, -1842, -1751, -1660, -1567, -1474, -1380, -1285, -1189, -1092, -995, -897, -799, -700, -601, -501, -401, -301, -201, -101};
static const int TRIS[12][3] = {{0,1,2},{0,2,3},{5,4,7},{5,7,6},{4,0,3},{4,3,7},{1,5,6},{1,6,2},{3,2,6},{3,6,7},{4,5,1},{4,1,0}};
static const int FACECOL[6] = {0xE04040, 0x40E040, 0x4040E0, 0xE0E040, 0x40E0E0, 0xE040E0};
static const int CUBE[8][3] = {{-100,-100,-100},{100,-100,-100},{100,100,-100},{-100,100,-100},{-100,-100,100},{100,-100,100},{100,100,100},{-100,100,100}};
typedef struct { long x, y, z; } V;
typedef struct { V a, b, c; int color; long depth; int ord; } Tri;
static long fdiv(long a, long b) { long q = a / b; if ((a % b != 0) && ((a < 0) != (b < 0))) q--; return q; }
static long fmodl_(long a, long b) { long r = a % b; if (r < 0) r += b < 0 ? -b : b; return r; }
static long sn(long a) { return SINES[fmodl_(a, 256)]; }
static long cs(long a) { return sn(a + 64); }
static long clampl(long v, long lo, long hi) { return v < lo ? lo : v > hi ? hi : v; }
static int pix[H][W];
static int cmp(const void *x, const void *y) {      /* farthest first; ties: earlier ord first */
  const Tri *p = x, *q = y;
  if (p->depth != q->depth) return p->depth > q->depth ? -1 : 1;
  return p->ord - q->ord;
}
static void edge(V p, V q, long y, long *lo, long *hi, int *any) {
  if (p.y == q.y) return;
  long a = p.y < q.y ? p.y : q.y, b = p.y < q.y ? q.y : p.y;
  if (y < a || y > b) return;
  long x = p.x + fdiv((y - p.y) * (q.x - p.x), q.y - p.y);
  if (!*any || x < *lo) *lo = x; if (!*any || x > *hi) *hi = x; *any = 1;
}
int main(int argc, char **argv) {
  long n = argc > 1 ? atol(argv[1]) : 120, total = 0;
  Tri tr[48];
  for (long t = 0; t < n; t++) {
    int k = 0;
    for (int i = 0; i < 4; i++) {
      long ox = -240 + 160 * i, ax = 2 * t + 17 * i, ay = 3 * t + 40 * i; V vs[8];
      for (int j = 0; j < 8; j++) {
        long x = CUBE[j][0], y = CUBE[j][1], z = CUBE[j][2];
        long x1 = fdiv(x * cs(ay) + z * sn(ay), 4096), z1 = fdiv(z * cs(ay) - x * sn(ay), 4096);
        long y2 = fdiv(y * cs(ax) - z1 * sn(ax), 4096), z2 = fdiv(y * sn(ax) + z1 * cs(ax), 4096);
        long wx = x1 + ox, wz = z2 + 700;
        vs[j] = (V){160 + fdiv(wx * 256, wz), 120 - fdiv(y2 * 256, wz), wz};
      }
      for (int m = 0; m < 12; m++) {
        V a = vs[TRIS[m][0]], b = vs[TRIS[m][1]], c = vs[TRIS[m][2]];
        if ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) >= 0) continue;
        long depth = a.z + b.z + c.z, s = clampl(512 - fdiv(depth, 8), 64, 256);
        int col = FACECOL[m / 2];
        int r = fdiv(((col >> 16) & 255) * s, 256), g = fdiv(((col >> 8) & 255) * s, 256), bl = fdiv((col & 255) * s, 256);
        tr[k++] = (Tri){a, b, c, (r << 16) | (g << 8) | bl, depth, i * 12 + m};
      }
    }
    qsort(tr, k, sizeof(Tri), cmp);
    for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) pix[y][x] = 0;
    for (int j = 0; j < k; j++) {
      long ymin = tr[j].a.y, ymax = ymin;
      V p3[3] = {tr[j].a, tr[j].b, tr[j].c};
      for (int q = 1; q < 3; q++) { if (p3[q].y < ymin) ymin = p3[q].y; if (p3[q].y > ymax) ymax = p3[q].y; }
      for (long y = ymin < 0 ? 0 : ymin; y <= (ymax > H - 1 ? H - 1 : ymax); y++) {
        long lo = 0, hi = 0; int any = 0;
        edge(tr[j].a, tr[j].b, y, &lo, &hi, &any); edge(tr[j].b, tr[j].c, y, &lo, &hi, &any); edge(tr[j].c, tr[j].a, y, &lo, &hi, &any);
        if (!any) continue;
        long x0 = lo < 0 ? 0 : lo, x1 = hi > W - 1 ? W - 1 : hi;
        for (long x = x0; x <= x1; x++) pix[y][x] = tr[j].color;
      }
    }
    long f = 0;
    for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) f = (f + (long)pix[y][x] * (x + 1 + y)) % 1000000007;
    total = (total * 7 + f) % 1000000007;
  }
  printf("checksum %ld\n", total);
  return 0;
}
