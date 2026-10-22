///|
fn main raise {
  let cost = try! @graphml.Key::new(
    "cost",
    @graphml.EdgeScope,
    @graphml.Int64,
    default_value=@graphml.LongValue(9007199254740993L),
  )
  let builder = try! @graphml.FlatBuilder::new([cost], @graphml.Directed)
  for id in ["api", "database", "metrics", "isolated"] {
    try! builder.add_node(id)
  }
  try! builder.add_edge("api", "database", id="sql")
  try! builder.add_edge("api", "database", id="backup", attributes=[
    ("cost", @graphml.LongValue(0L)),
  ])
  try! builder.add_edge("api", "metrics", id="telemetry")
  let source = try! builder.finish()
  let selected = try! source
    .flat_graph(@graphml.GraphAddress::root(0))
    .induced_subgraph(["database", "api", "isolated"])
  assert_eq(source.statistics().edges, 3)
  assert_eq(selected.statistics().edges, 2)
  assert_true(
    selected.equivalent(try! @graphml.parse(@graphml.serialize(selected))),
  )
  let flat = try! selected.flat_graph(@graphml.GraphAddress::root(0))
  let outgoing = try! flat.to_csr()
  let incoming = try! flat.to_csr(orientation=@graphml.Incoming)
  let database = incoming.node_index("database").unwrap()
  let dependencies = try! incoming.row(database)
  assert_eq(dependencies.length(), 2)
  assert_eq(outgoing.indptr(), [0, 2, 2, 2])
  let weights = try! flat.edge_rows()
  for entry in dependencies {
    // Joining by original edge ordinal preserves Int64 and defaults without
    // converting values to floating point or combining parallel relationships.
    let value = weights[entry.edge_index].attributes.get("cost").unwrap()
    println("edge=\{entry.edge_index} exact-cost=\{value.lexical()}")
  }
  assert_true(
    weights[0].attributes.get("cost")
    is Some(@graphml.LongValue(9007199254740993L)),
  )
  assert_true(weights[1].attributes.get("cost") is Some(@graphml.LongValue(0L)))
  println(
    "selected nodes=\{outgoing.node_count()} arcs=\{outgoing.arc_count()}",
  )
}
