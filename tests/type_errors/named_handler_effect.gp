# expect: expected Fn(Request) -> Response, got Fn(Request) -> Response ! [io]
import http
fn handle(req: Request) -> Response ! [io]
  println(req.path)
  http.html(200, "hi")
end
fn main() -> Unit ! [io, net]
  match http.serve("127.0.0.1:8080", handle)
    case Ok(_) -> Unit
    case Err(e) -> println(e)
  end
end
