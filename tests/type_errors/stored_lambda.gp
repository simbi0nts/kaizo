# expect: main calls tcp_close, which has effect net, but main does not declare it
fn main() -> Unit ! [io]
  let send = fn(x) tcp_close(x) end
  println("closing")
  send(Unit)
end
