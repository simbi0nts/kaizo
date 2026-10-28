# server — HTTP hello server under load
Same model in every language: one thread, blocking accept; per connection read the request head
(until "\r\n\r\n"), answer `<h1>Hello, world</h1>` with the exact headers of libs/http
(Content-Type text/html; charset=utf-8, Content-Length, Connection: close), close.
Port = argv[1]. Load: bench/server/load.c — N client threads, each connect → GET / → read to EOF →
close, for D seconds; reports requests/s, p50/p99 latency, errors.
