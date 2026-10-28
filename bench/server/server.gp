import http

fn handle(req: Request) -> Response
  http.html(200, "<h1>Hello, world</h1>")
end

fn main() -> Unit ! [io, net]
  let port = unwrap_or(str_to_int(unwrap_or(list_get(args(), 0), "18090")), 18090)
  match http.serve(str_cat("127.0.0.1:", show(port)), handle)
    case Ok(_) -> Unit
    case Err(e) -> println(e)
  end
end
