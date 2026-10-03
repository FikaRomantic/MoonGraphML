///|
test "key scopes and typed defaults" {
  for
    name in [
      "all", "graphml", "graph", "node", "edge", "port", "hyperedge", "endpoint",
    ] {
    assert_eq(try! Scope::from_name(name).name(), name)
  }
  let key = try! Key::new(
    "weight",
    EdgeScope,
    Float64,
    default_value=DoubleValue(1.5),
  )
  assert_true(key.scope.applies_to(EdgeScope))
  assert_true(!key.scope.applies_to(NodeScope))
  assert_true(All.applies_to(NodeScope))
  assert_true(
    try {
      let _ = Key::new("k", NodeScope, Boolean, default_value=IntegerValue(0))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "GraphML identifiers allow NMTOKEN digits and Unicode" {
  for token in ["0", "n-1", "设备:1", "a.b", "😀"] {
    try! valid_token(token, "test")
  }
  for token in ["", "a b", "n/1", "a\n"] {
    assert_true(
      try {
        valid_token(token, "test")
        false
      } catch {
        _ => true
      },
    )
  }
}
