# Pure, seedable pseudo-random numbers (LCG, 31-bit state). No effects: reproducible in tests.

type Rng = { state: Int } end
type Roll = { value: Int, rng: Rng } end

let modulus = 2147483648

fn seeded(seed: Int) -> Rng
  Rng { state: mod(seed, modulus) }
end

fn next(r: Rng) -> Rng
  Rng { state: mod(add(mul(r.state, 1103515245), 12345), modulus) }
end

# below: a value in [0, n); 0 when n <= 0
fn below(r: Rng, n: Int) -> Roll
  let r2 = next(r)
  if le(n, 0) then
    Roll { value: 0, rng: r2 }
  else
    Roll { value: mod(div(r2.state, 65536), n), rng: r2 }
  end
end

test "same seed, same sequence"
  expect_eq(below(seeded(42), 100), below(seeded(42), 100))
end

test "values stay in range"
  let rolls = list_fold(list_range(0, 200), Roll { value: 0, rng: seeded(7) }, fn(acc, i)
    let r = below(acc.rng, 10)
    expect(and(ge(r.value, 0), lt(r.value, 10)), "out of range")
    r
  end)
  expect(ge(rolls.value, 0), "last roll")
end

test "non-positive bound gives 0"
  expect_eq(below(seeded(1), 0).value, 0)
end
