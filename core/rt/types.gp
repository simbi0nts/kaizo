# Types and effects of the builtins, for the type checker (bodies are never used).
# Function arguments of builtins are effect-transparent: list_map(l, f) has the effects of f. Single capital letters
# are type variables. Keep in sync with builtin_list in program.gp and with rt.gp.

fn add(a: Int, b: Int) -> Int Unit end
fn sub(a: Int, b: Int) -> Int Unit end
fn mul(a: Int, b: Int) -> Int Unit end
fn div(a: Int, b: Int) -> Int Unit end
fn mod(a: Int, b: Int) -> Int Unit end
fn eq(a: A, b: A) -> Bool Unit end
fn ne(a: A, b: A) -> Bool Unit end
fn lt(a: A, b: A) -> Bool Unit end
fn le(a: A, b: A) -> Bool Unit end
fn gt(a: A, b: A) -> Bool Unit end
fn ge(a: A, b: A) -> Bool Unit end
fn not(a: Bool) -> Bool Unit end
fn and(a: Bool, b: Bool) -> Bool Unit end
fn or(a: Bool, b: Bool) -> Bool Unit end
fn bit_and(a: Int, b: Int) -> Int Unit end
fn bit_or(a: Int, b: Int) -> Int Unit end
fn bit_xor(a: Int, b: Int) -> Int Unit end
fn bit_shl(a: Int, n: Int) -> Int Unit end
fn bit_shr(a: Int, n: Int) -> Int Unit end
fn target() -> String Unit end
fn show(v: A) -> String Unit end
fn str_cat(a: String, b: String) -> String Unit end
fn str_join(l: List[String], sep: String) -> String Unit end
fn str_len(s: String) -> Int Unit end
fn str_slice(s: String, from: Int, to: Int) -> String Unit end
fn str_find(s: String, sub: String) -> Option[Int] Unit end
fn str_split(s: String, sep: String) -> List[String] Unit end
fn str_trim(s: String) -> String Unit end
fn str_starts(s: String, p: String) -> Bool Unit end
fn str_ends(s: String, p: String) -> Bool Unit end
fn str_repeat(s: String, n: Int) -> String Unit end
fn str_lower(s: String) -> String Unit end
fn str_to_int(s: String) -> Option[Int] Unit end
fn str_byte(s: String, i: Int) -> Int Unit end
fn str_from_bytes(l: List[Int]) -> String Unit end
fn list_len(l: List[A]) -> Int Unit end
fn list_get(l: List[A], i: Int) -> Option[A] Unit end
fn list_cons(x: A, l: List[A]) -> List[A] Unit end
fn list_push(l: List[A], x: A) -> List[A] Unit end
fn list_concat(a: List[A], b: List[A]) -> List[A] Unit end
fn list_slice(l: List[A], from: Int, to: Int) -> List[A] Unit end
fn list_reverse(l: List[A]) -> List[A] Unit end
fn list_range(from: Int, to: Int) -> List[Int] Unit end
fn list_contains(l: List[A], x: A) -> Bool Unit end
fn list_map(l: List[A], f: Fn(A) -> B) -> List[B] Unit end
fn list_filter(l: List[A], f: Fn(A) -> Bool) -> List[A] Unit end
fn list_fold(l: List[A], init: B, f: Fn(B, A) -> B) -> B Unit end
fn list_sort(l: List[A]) -> List[A] Unit end
fn list_sort_by(l: List[A], before: Fn(A, A) -> Bool) -> List[A] Unit end
fn panic(msg: A) -> B Unit end
fn expect(c: Bool, msg: A) -> Unit Unit end
fn expect_eq(got: A, want: A) -> Unit Unit end
fn embed_file(path: String) -> String Unit end
fn print(s: String) -> Unit ! [io] Unit end
fn println(s: String) -> Unit ! [io] Unit end
fn read_line() -> Option[String] ! [io] Unit end
fn read_all() -> String ! [io] Unit end
fn args() -> List[String] ! [io] Unit end
fn exit(code: Int) -> Unit ! [io] Unit end
fn env_get(name: String) -> Option[String] ! [io] Unit end
fn term_raw() -> Result[Unit, String] ! [term] Unit end
fn term_restore() -> Unit ! [term] Unit end
fn term_key() -> String ! [term] Unit end
fn now_ms() -> Int ! [time] Unit end
fn sleep_ms(n: Int) -> Unit ! [time] Unit end
fn tcp_listen(addr: String) -> Result[Listener, String] ! [net] Unit end
fn tcp_accept(l: Listener) -> Result[Conn, String] ! [net] Unit end
fn tcp_read(c: Conn, max: Int, timeout: Int) -> Result[String, String] ! [net] Unit end
fn tcp_write(c: Conn, s: String) -> Result[Unit, String] ! [net] Unit end
fn tcp_close(c: A) -> Unit ! [net] Unit end
fn unix_connect(path: String) -> Result[Conn, String] ! [net] Unit end
fn read_file(path: String) -> Result[String, String] ! [fs] Unit end
fn write_file(path: String, s: String, mode: Int) -> Result[Unit, String] ! [fs] Unit end
fn list_dir(path: String) -> Result[List[String], String] ! [fs] Unit end
fn run_image(bin: String, args: List[String]) -> Result[Unit, String] ! [proc] Unit end
