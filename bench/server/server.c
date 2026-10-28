#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
static const char RESP[] = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: 21\r\nConnection: close\r\n\r\n<h1>Hello, world</h1>";
int main(int argc, char **argv) {
  int port = argc > 1 ? atoi(argv[1]) : 18091, one = 1;
  int ls = socket(AF_INET, SOCK_STREAM, 0);
  setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
  struct sockaddr_in a = {0}; a.sin_family = AF_INET; a.sin_port = htons(port); a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (bind(ls, (struct sockaddr *)&a, sizeof a) || listen(ls, 1024)) { perror("listen"); return 1; }
  char buf[4096];
  for (;;) {
    int c = accept(ls, NULL, NULL); if (c < 0) continue;
    size_t n = 0;
    while (n < sizeof buf - 1) {
      ssize_t r = read(c, buf + n, sizeof buf - 1 - n); if (r <= 0) break; n += r; buf[n] = 0;
      if (strstr(buf, "\r\n\r\n")) break;
    }
    write(c, RESP, sizeof RESP - 1);
    close(c);
  }
}
