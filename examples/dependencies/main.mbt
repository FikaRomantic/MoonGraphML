///|
fn main raise {
  let keys = [
    try! @graphml.Key::new(
      "kind",
      @graphml.NodeScope,
      @graphml.StringValue,
      name="kind",
    ),
  ]
  let builder = try! @graphml.FlatBuilder::new(
    keys,
    @graphml.Directed,
    graph_id="services",
  )
  try! builder.add_node("api", attributes=[
    ("kind", @graphml.TextValue("service")),
  ])
  try! builder.add_node("db", attributes=[
    ("kind", @graphml.TextValue("database")),
  ])
  try! builder.add_edge("api", "db", id="uses")
  let document = try! builder.finish()
  let encoded = try! @graphml.serialize(document)
  assert_true(document.equivalent(try! @graphml.parse(encoded)))
  let index = @graphml.GraphIndex::new(document)
  assert_eq(index.incident_edges(0, "db").length(), 1)
  println(encoded)
}
