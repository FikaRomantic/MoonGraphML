///|
test "simultaneous relabel handles cyclic IDs and all port hyperedge references" {
  let graph = {
    ..Graph::new(Directed),
    nodes: [{ ..Node::new("a"), ports: [Port::new("p")], }, Node::new("b")],
    edges: [Edge::new("a", "b", source_port="p")],
    hyperedges: [
      {
        ..Hyperedge::new(),
        endpoints: [Endpoint::new("a", port="p"), Endpoint::new("b")],
      },
    ],
  }
  let doc = Document::new([], [graph])
  let swapped = doc.relabel_nodes(0, [("a", "b"), ("b", "a")])
  let result = swapped.graphs()[0]
  assert_eq(result.nodes[0].id, "b")
  assert_eq(result.edges[0].source, "b")
  assert_eq(result.edges[0].target, "a")
  assert_eq(result.edges[0].source_port, Some("p"))
  assert_eq(result.hyperedges[0].endpoints[0].node, "b")
  assert_true(parse(serialize(swapped)).equivalent(swapped))
  assert_eq(doc.graphs()[0].nodes[0].id, "a")
}

///|
test "relabel rejects final collisions unknown keys and repeated sources atomically" {
  let doc = Document::new([], [
    { ..Graph::new(Directed), nodes: [Node::new("a"), Node::new("b")], },
  ])
  for
    pairs in [[("a", "b")], [("z", "x")], [("a", "x"), ("a", "y")], [("a", "")]] {
    let bad = try {
      ignore(doc.relabel_nodes(0, pairs))
      false
    } catch {
      _ => true
    }
    assert_true(bad)
  }
  assert_eq(doc.graphs()[0].nodes[0].id, "a")
}

///|
test "edge selection distinguishes parallel anonymous edges and keeps selected endpoints" {
  let doc = Document::new([], [
    {
      ..Graph::new(Directed),
      nodes: [Node::new("a"), Node::new("b"), Node::new("c")],
      edges: [Edge::new("a", "b"), Edge::new("a", "b"), Edge::new("b", "b")],
    },
  ])
  let flat = doc.flat_graph(GraphAddress::root(0))
  let filtered = flat.edge_subgraph([2, 1]).graphs()[0]
  assert_eq(filtered.nodes.length(), 2)
  assert_eq(filtered.edges.length(), 2)
  assert_eq(filtered.edges[0].source, "a")
  assert_eq(filtered.edges[1].source, "b")
  assert_eq(
    flat.edge_subgraph([], keep_isolated=true).graphs()[0].nodes.length(),
    3,
  )
  assert_eq(flat.edge_subgraph([]).graphs()[0].nodes.length(), 0)
  for indices in [[3], [-1], [0, 0]] {
    let bad = try {
      ignore(flat.edge_subgraph(indices))
      false
    } catch {
      _ => true
    }
    assert_true(bad)
  }
}
