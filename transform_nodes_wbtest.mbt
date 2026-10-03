///|
test "node rename rewrites ancestor edges and hyperedge endpoints only in selected root" {
  let doc = try! parse(
    "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><graph edgedefault=\"directed\"><node id=\"a\"><graph edgedefault=\"directed\"><node id=\"b\"/></graph></node><edge source=\"b\" target=\"b\"/><hyperedge><endpoint node=\"b\"/></hyperedge></graph><graph edgedefault=\"undirected\"><node id=\"b\"/></graph></graphml>",
  )
  let renamed = try! doc.rename_node(0, "b", "new")
  let graphs = renamed.graphs()
  assert_eq(graphs[0].edges[0].source, "new")
  assert_eq(graphs[0].edges[0].target, "new")
  assert_eq(graphs[0].hyperedges[0].endpoints[0].node, "new")
  assert_eq(graphs[1].nodes[0].id, "b")
  assert_true(
    try {
      let _ = doc.rename_node(0, "b", "a")
      false
    } catch {
      _ => true
    },
  )
  let address = GraphIndex::new(doc).node_address(0, "b").unwrap()
  assert_true(
    try {
      let _ = doc.replace_node(address, Node::new("other"))
      false
    } catch {
      _ => true
    },
  )
}
