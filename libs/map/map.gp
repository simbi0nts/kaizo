# Persistent (immutable) map with String keys: an AVL tree. All operations O(log n).

type Map[V] = MapLeaf | MapNode(Map[V], String, V, Map[V], Int) end
type Entry[V] = { key: String, value: V } end

fn empty() -> Map[V]
  MapLeaf
end

fn height(m: Map[V]) -> Int
  match m
    case MapLeaf -> 0
    case MapNode(_, _, _, _, h) -> h
  end
end

fn node(l: Map[V], k: String, v: V, r: Map[V]) -> Map[V]
  MapNode(l, k, v, r, add(max(height(l), height(r)), 1))
end

fn rotate_right(m: Map[V]) -> Map[V]
  match m
    case MapNode(MapNode(ll, lk, lv, lr, _), k, v, r, _) -> node(ll, lk, lv, node(lr, k, v, r))
    case _ -> m
  end
end

fn rotate_left(m: Map[V]) -> Map[V]
  match m
    case MapNode(l, k, v, MapNode(rl, rk, rv, rr, _), _) -> node(node(l, k, v, rl), rk, rv, rr)
    case _ -> m
  end
end

fn balance(l: Map[V], k: String, v: V, r: Map[V]) -> Map[V]
  let hl = height(l)
  let hr = height(r)
  if gt(hl, add(hr, 1)) then
    match l
      case MapNode(ll, _, _, lr, _) ->
        if ge(height(ll), height(lr)) then rotate_right(node(l, k, v, r)) else rotate_right(node(rotate_left(l), k, v, r)) end
      case MapLeaf -> node(l, k, v, r)
    end
  elif gt(hr, add(hl, 1)) then
    match r
      case MapNode(rl, _, _, rr, _) ->
        if ge(height(rr), height(rl)) then rotate_left(node(l, k, v, r)) else rotate_left(node(l, k, v, rotate_right(r))) end
      case MapLeaf -> node(l, k, v, r)
    end
  else
    node(l, k, v, r)
  end
end

fn set(m: Map[V], key: String, value: V) -> Map[V]
  match m
    case MapLeaf -> MapNode(MapLeaf, key, value, MapLeaf, 1)
    case MapNode(l, k, v, r, h) ->
      if lt(key, k) then balance(set(l, key, value), k, v, r)
      elif gt(key, k) then balance(l, k, v, set(r, key, value))
      else MapNode(l, k, value, r, h)
      end
  end
end

fn get(m: Map[V], key: String) -> Option[V]
  match m
    case MapLeaf -> None
    case MapNode(l, k, v, r, _) ->
      if lt(key, k) then get(l, key) elif gt(key, k) then get(r, key) else Some(v) end
  end
end

fn has(m: Map[V], key: String) -> Bool
  is_some(get(m, key))
end

fn size(m: Map[V]) -> Int
  match m
    case MapLeaf -> 0
    case MapNode(l, _, _, r, _) -> add(add(size(l), size(r)), 1)
  end
end

fn entries_acc(m: Map[V], acc: List[Entry[V]]) -> List[Entry[V]]
  match m
    case MapLeaf -> acc
    case MapNode(l, k, v, r, _) -> entries_acc(l, list_cons(Entry { key: k, value: v }, entries_acc(r, acc)))
  end
end

# entries in key order
fn entries(m: Map[V]) -> List[Entry[V]]
  entries_acc(m, [])
end

fn keys(m: Map[V]) -> List[String]
  list_map(entries(m), fn(e) e.key end)
end

test "set, get, overwrite"
  let m = set(set(set(empty(), "b", 2), "a", 1), "b", 3)
  expect_eq(get(m, "a"), Some(1))
  expect_eq(get(m, "b"), Some(3))
  expect_eq(get(m, "c"), None)
  expect_eq(size(m), 2)
end

test "stays balanced on sorted inserts"
  let m = list_fold(list_range(0, 1000), empty(), fn(acc, i) set(acc, str_cat("k", show(add(10000, i))), i) end)
  expect_eq(size(m), 1000)
  expect(le(height(m), 11), "AVL height for 1000 keys must be <= 11")
  expect_eq(get(m, "k10500"), Some(500))
  expect_eq(list_get(keys(m), 0), Some("k10000"))
end
