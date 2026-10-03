///|
test "edge override preserves direction separately from graph default" {
  let graph = Graph::new(Directed)
  assert_eq(Edge::new("a", "b").effective_direction(graph), Directed)
  let edge = Edge::new("a", "b", directed=false)
  assert_eq(edge.effective_direction(graph), Undirected)
  assert_eq(edge.directed, Some(false))
}

///|
test "model supports ports and nonbinary connections" {
  let node = Node::new("设备")
  node.ports.push(Port::new("eth0"))
  assert_eq(node.ports[0].name, "eth0")
  let hyperedge = Hyperedge::new(id="bus")
  for id in ["a", "b", "c"] {
    hyperedge.endpoints.push(Endpoint::new(id))
  }
  assert_eq(hyperedge.endpoints.length(), 3)
  assert_eq(hyperedge.endpoints[0].kind, Undir)
}
