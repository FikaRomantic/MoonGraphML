///|
test "typed rows preserve mixed direction loops and parallel edges" {
  let keys = [
    try! Key::new("weight", EdgeScope, Float64, default_value=DoubleValue(1.5)),
  ]
  let doc = try! from_rows(
    keys,
    [{ id: "a", attributes: Map([]), }, { id: "b", attributes: Map([]), }],
    [
      {
        id: Some("1"),
        source: "a",
        target: "b",
        direction: Directed,
        attributes: Map([]),
      },
      {
        id: Some("2"),
        source: "a",
        target: "b",
        direction: Undirected,
        attributes: Map([]),
      },
      {
        id: None,
        source: "b",
        target: "b",
        direction: Directed,
        attributes: Map([]),
      },
    ],
  )
  let flat = try! doc.flat_graph(GraphAddress::root(0))
  assert_eq(flat.indexed_edges().length(), 3)
  assert_eq(flat.indexed_edges()[2].source, 1)
  assert_eq(flat.indexed_edges()[1].direction, Undirected)
  let rows = try! flat.edge_rows()
  assert_true(rows[0].attributes.get("weight") is Some(DoubleValue(1.5)))
  assert_eq(try! flat.edge_rows(use_defaults=false)[0].attributes.length(), 0)
  assert_eq(
    try! from_rows(keys, flat.node_rows(), rows).graphs()[0].edges.length(),
    3,
  )
}

///|
test "flat adapter rejects lossy advanced conversion and unknown table keys" {
  let graph = Graph::new(Directed)
  let node = Node::new("a")
  node.ports.push(Port::new("p"))
  graph.nodes.push(node)
  let doc = try! Document::new([], [graph])
  assert_true(
    try {
      let _ = doc.flat_graph(GraphAddress::root(0))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = from_rows(
        [],
        [{ id: "a", attributes: Map([("missing", TextValue("x"))]), }],
        [],
      )
      false
    } catch {
      _ => true
    },
  )
}
