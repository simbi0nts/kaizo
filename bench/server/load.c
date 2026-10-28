/* load <port> <threads> <seconds>: closed-loop HTTP/1.0-style clients (new connection per request) */
#include <arpa/inet.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
static int port; static double secs; static volatile int stop;
typedef struct { long ok, err, nlat; double *lat; } R;
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
static void *client(void *arg) {
  R *r = arg; char buf[4096]; const char *req = "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n";
  struct sockaddr_in a = {0}; a.sin_family = AF_INET; a.sin_port = htons(port); a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  while (!stop) {
    double t0 = now();
    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (connect(s, (struct sockaddr *)&a, sizeof a)) { close(s); r->err++; continue; }
    if (write(s, req, strlen(req)) < 0) { close(s); r->err++; continue; }
    long got = 0; ssize_t k;
    while ((k = read(s, buf, sizeof buf)) > 0) got += k;
    close(s);
    if (got > 0 && memcmp(buf, "HTTP/1.1 200", 12) == 0) {
      r->ok++; if (r->nlat < 2000000) r->lat[r->nlat++] = now() - t0;
    } else r->err++;
  }
  return NULL;
}
static int cmpd(const void *a, const void *b) { double x = *(double *)a, y = *(double *)b; return x < y ? -1 : x > y; }
int main(int argc, char **argv) {
  port = atoi(argv[1]); int th = atoi(argv[2]); secs = atof(argv[3]);
  pthread_t t[256]; R r[256];
  for (int i = 0; i < th; i++) { r[i] = (R){0, 0, 0, malloc(sizeof(double) * 2000000)}; pthread_create(&t[i], NULL, client, &r[i]); }
  usleep((useconds_t)(secs * 1e6)); stop = 1;
  long ok = 0, err = 0, n = 0;
  for (int i = 0; i < th; i++) { pthread_join(t[i], NULL); ok += r[i].ok; err += r[i].err; n += r[i].nlat; }
  double *all = malloc(sizeof(double) * (n ? n : 1)); long k = 0;
  for (int i = 0; i < th; i++) for (long j = 0; j < r[i].nlat; j++) all[k++] = r[i].lat[j];
  qsort(all, n, sizeof(double), cmpd);
  printf("rps %.0f p50_ms %.3f p99_ms %.3f errors %ld\n", ok / secs, n ? all[n / 2] * 1e3 : 0, n ? all[n * 99 / 100] * 1e3 : 0, err);
  return 0;
}
