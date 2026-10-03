///|
test "nested graph replacement checks references held by ancestors" {
  let doc = try! parse(
    "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><graph edgedefault=\"directed\"><node id=\"a\"><graph edgedefault=\"directed\"><node id=\"b\"/></graph></node><edge source=\"a\" target=\"b\"/></graph></graphml>",
  )
  let address = GraphAddress::root(0).child(NodeGraph(0))
  assert_true(
    try {
      let _ = doc.replace_graph(address, Graph::new(Directed))
      false
    } catch {
      _ => true
    },
  )
  let graph = try! doc.graph_at(address)
  graph.nodes.push(Node::new("c"))
  let updated = try! doc.replace_graph(address, graph)
  assert_eq(try! updated.graph_at(address).nodes.length(), 2)
  assert_eq(try! doc.graph_at(address).nodes.length(), 1)
}

///|
test "top-level selection keeps independent ID scopes and detects duplicates" {
  let graph = Graph::new(Directed)
  graph.nodes.push(Node::new("a"))
  let doc = try! Document::new([], [graph, graph])
  assert_eq(try! doc.select_graphs([1]).graph_count(), 1)
  assert_eq(try! doc.append_graph(Graph::new(Undirected)).graph_count(), 3)
  assert_true(
    try {
      let _ = doc.select_graphs([0, 0])
      false
    } catch {
      _ => true
    },
  )
}
