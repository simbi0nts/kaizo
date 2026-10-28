# expect: error: expected end to close the block, found ")"
fn main() -> Unit ! [io]
  let failed = true
  exit(if failed then 1 else 0)
end
