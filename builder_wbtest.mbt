///|
test "batch builder resolves forward references and detaches finished snapshots" {
  let builder = try! FlatBuilder::new(
    [Key::new("weight", EdgeScope, Int32)],
    Directed,
  )
  try! builder.add_edge("a", "b", id="e", attributes=[
    ("weight", IntegerValue(2)),
  ])
  assert_true(
    try {
      let _ = builder.finish()
      false
    } catch {
      _ => true
    },
  )
  try! builder.add_node("a")
  try! builder.add_node("b")
  let first = try! builder.finish()
  try! builder.add_node("c")
  assert_eq(first.statistics().nodes, 2)
  assert_eq(try! builder.finish().statistics().nodes, 3)
  assert_eq(builder.edge_count(), 1)
}

///|
test "builder validates additions atomically" {
  let builder = try! FlatBuilder::new(
    [Key::new("number", NodeScope, Int32)],
    Directed,
    limits={ ..Limits::default(), nodes: 1, },
  )
  assert_true(
    try {
      builder.add_node("a", attributes=[("number", TextValue("1"))])
      false
    } catch {
      _ => true
    },
  )
  assert_eq(builder.node_count(), 0)
  try! builder.add_node("a", attributes=[("number", IntegerValue(1))])
  assert_true(
    try {
      builder.add_node("b")
      false
    } catch {
      LimitExceeded(..) => true
      _ => false
    },
  )
  assert_eq(builder.node_count(), 1)
  assert_true(
    try {
      builder.add_edge("a", "a", id="e", attributes=[
        ("number", IntegerValue(1)),
      ])
      false
    } catch {
      _ => true
    },
  )
  assert_eq(builder.edge_count(), 0)
  try! builder.add_edge("a", "a", id="e")
  assert_eq(try! builder.finish().statistics().edges, 1)
}
