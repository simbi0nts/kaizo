# expect: this function uses io, but the function type it is passed as allows no effects
import http
fn main() -> Unit ! [io, net]
  match http.serve("127.0.0.1:8080", fn(req) 
    println("got a request")
    http.html(200, "hi")
  end)
    case Ok(_) -> Unit
    case Err(e) -> println(e)
  end
end
