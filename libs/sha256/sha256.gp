# SHA-256 (FIPS 180-4) over byte strings. Used by kaizo for macOS code signatures.

let mask = 4294967295

let k = [1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221,
  3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580,
  3835390401, 4022224774, 264347078, 604807628, 770255983, 1249150122, 1555081692, 1996064986,
  2554220882, 2821834349, 2952996808, 3210313671, 3336571891, 3584528711, 113926993, 338241895,
  666307205, 773529912, 1294757372, 1396182291, 1695183700, 1986661051, 2177026350, 2456956037,
  2730485921, 2820302411, 3259730800, 3345764771, 3516065817, 3600352804, 4094571909, 275423344,
  430227734, 506948616, 659060556, 883997877, 958139571, 1322822218, 1537002063, 1747873779,
  1955562222, 2024104815, 2227730452, 2361852424, 2428436474, 2756734187, 3204031479, 3329325298]

let h0 = [1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635, 1541459225]

fn rotr(x: Int, n: Int) -> Int
  bit_and(bit_or(bit_shr(x, n), bit_shl(x, sub(32, n))), mask)
end

fn add32(a: Int, b: Int) -> Int
  bit_and(add(a, b), mask)
end

fn kw(i: Int) -> Int
  unwrap_or(list_get(k, i), 0)
end

fn word_be(s: String, off: Int) -> Int
  add(add(mul(str_byte(s, off), 16777216), mul(str_byte(s, add(off, 1)), 65536)), add(mul(str_byte(s, add(off, 2)), 256), str_byte(s, add(off, 3))))
end

fn schedule(w: List[Int], i: Int) -> List[Int]
  if ge(i, 64) then w else
    let w15 = unwrap_or(list_get(w, sub(i, 15)), 0)
    let w2 = unwrap_or(list_get(w, sub(i, 2)), 0)
    let s0 = bit_xor(bit_xor(rotr(w15, 7), rotr(w15, 18)), bit_shr(w15, 3))
    let s1 = bit_xor(bit_xor(rotr(w2, 17), rotr(w2, 19)), bit_shr(w2, 10))
    let v = add32(add32(unwrap_or(list_get(w, sub(i, 16)), 0), s0), add32(unwrap_or(list_get(w, sub(i, 7)), 0), s1))
    schedule(list_push(w, v), add(i, 1))
  end
end

type St = { a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int } end

fn rounds(s: St, w: List[Int], i: Int) -> St
  if ge(i, 64) then s else
    let s1 = bit_xor(bit_xor(rotr(s.e, 6), rotr(s.e, 11)), rotr(s.e, 25))
    let ch = bit_xor(bit_and(s.e, s.f), bit_and(bit_xor(s.e, mask), s.g))
    let t1 = add32(add32(add32(s.h, s1), add32(ch, kw(i))), unwrap_or(list_get(w, i), 0))
    let s0 = bit_xor(bit_xor(rotr(s.a, 2), rotr(s.a, 13)), rotr(s.a, 22))
    let maj = bit_xor(bit_xor(bit_and(s.a, s.b), bit_and(s.a, s.c)), bit_and(s.b, s.c))
    let t2 = add32(s0, maj)
    rounds(St { a: add32(t1, t2), b: s.a, c: s.b, d: s.c, e: add32(s.d, t1), f: s.e, g: s.f, h: s.g }, w, add(i, 1))
  end
end

fn block(hs: List[Int], s: String, off: Int) -> List[Int]
  let w = schedule(list_map(list_range(0, 16), fn(i) word_be(s, add(off, mul(4, i))) end), 16)
  let g = fn(i) unwrap_or(list_get(hs, i), 0) end
  let r = rounds(St { a: g(0), b: g(1), c: g(2), d: g(3), e: g(4), f: g(5), g: g(6), h: g(7) }, w, 0)
  [add32(g(0), r.a), add32(g(1), r.b), add32(g(2), r.c), add32(g(3), r.d), add32(g(4), r.e), add32(g(5), r.f), add32(g(6), r.g), add32(g(7), r.h)]
end

fn blocks(hs: List[Int], s: String, off: Int, n: Int) -> List[Int]
  if ge(off, n) then hs else blocks(block(hs, s, off), s, add(off, 64), n) end
end

fn be_bytes(v: Int, k2: Int) -> List[Int]
  list_reverse(list_map(list_range(0, k2), fn(i) bit_and(bit_shr(v, mul(8, i)), 255) end))
end

# 32-byte digest as a byte string
fn digest(msg: String) -> String
  let n = str_len(msg)
  let full = mul(div(n, 64), 64)
  let rest = str_slice(msg, full, n)
  let padlen = sub(if lt(str_len(rest), 56) then 56 else 120 end, str_len(rest))
  let tail = str_join([rest, str_from_bytes([128]), str_repeat(str_from_bytes([0]), sub(padlen, 1)), str_from_bytes(be_bytes(mul(n, 8), 8))], "")
  let hs = blocks(blocks(h0, msg, 0, full), tail, 0, str_len(tail))
  str_from_bytes(list_fold(hs, [], fn(acc, x) list_concat(acc, be_bytes(x, 4)) end))
end

fn hex(s: String) -> String
  let digits = "0123456789abcdef"
  str_join(list_map(list_range(0, str_len(s)), fn(i)
    let b = str_byte(s, i)
    str_cat(str_slice(digits, div(b, 16), add(div(b, 16), 1)), str_slice(digits, mod(b, 16), add(mod(b, 16), 1)))
  end), "")
end

test "empty"
  expect_eq(hex(digest("")), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
end

test "abc"
  expect_eq(hex(digest("abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
end

test "two blocks"
  expect_eq(hex(digest("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
end

test "4096 bytes"
  expect_eq(hex(digest(str_repeat("kaizo!!!", 512))), "2da017bc6078adedffb08bd7d4dfb3c5a93fba12b609b3fff7ded2cd9212fb94")
end
