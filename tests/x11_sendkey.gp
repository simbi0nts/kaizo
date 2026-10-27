# Test helper: send key presses to an X window.  kaizo run tests/x11_sendkey.gp <window-id-hex> <keycode>...
import x11

fn hex_value(s: String, i: Int, acc: Int) -> Int
  if ge(i, str_len(s)) then acc else
    let c = str_byte(s, i)
    let d = if and(ge(c, 48), le(c, 57)) then sub(c, 48) elif and(ge(c, 97), le(c, 102)) then sub(c, 87) else 0 end
    hex_value(s, add(i, 1), add(mul(acc, 16), d))
  end
end

fn main() -> Unit ! [io, fs, net, time]
  match args()
    case [win, ..codes] ->
      match x11.open()
        case Err(e) -> println(e)
        case Ok(x) ->
          let w = hex_value(str_lower(if str_starts(win, "0x") then str_slice(win, 2, str_len(win)) else win end), 0, 0)
          list_fold(codes, Unit, fn(acc, c)
            x11.send_key(x, w, unwrap_or(str_to_int(c), 0))
            Unit
          end)
          sleep_ms(50)
          x11.close(x)
      end
    case [] -> println("usage: x11_sendkey <window-id> <keycode>...")
  end
end
