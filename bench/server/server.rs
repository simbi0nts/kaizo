use std::io::{Read, Write};
use std::net::TcpListener;
const RESP: &[u8] = b"HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: 21\r\nConnection: close\r\n\r\n<h1>Hello, world</h1>";
fn main() {
    let port: u16 = std::env::args().nth(1).and_then(|s| s.parse().ok()).unwrap_or(18092);
    let l = TcpListener::bind(("127.0.0.1", port)).expect("bind");
    let mut buf = [0u8; 4096];
    for s in l.incoming() {
        let Ok(mut s) = s else { continue };
        let mut n = 0;
        while n < buf.len() {
            match s.read(&mut buf[n..]) { Ok(0) | Err(_) => break, Ok(r) => n += r }
            if buf[..n].windows(4).any(|w| w == b"\r\n\r\n") { break; }
        }
        let _ = s.write_all(RESP);
    }
}
