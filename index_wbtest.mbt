///|
test "index separates top-level scopes and retains anonymous edge locations" {
  let doc = try! parse(
    "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><graph id=\"outer\" edgedefault=\"directed\"><node id=\"a\"><graph id=\"inner\" edgedefault=\"undirected\"><node id=\"b\"/></graph></node><edge id=\"e\" source=\"a\" target=\"b\"/><edge source=\"b\" target=\"b\"/><hyperedge id=\"h\"><endpoint node=\"b\"/><endpoint node=\"b\"/></hyperedge></graph><graph edgedefault=\"undirected\"><node id=\"b\"/></graph></graphml>",
  )
  let index = GraphIndex::new(doc)
  assert_eq(
    index.graph_address("inner"),
    Some(GraphAddress::root(0).child(NodeGraph(0))),
  )
  assert_true(index.node(0, "b") is Some(_))
  assert_true(index.node(1, "b") is Some(_))
  assert_true(index.node(2, "b") is None)
  let incident = index.incident_edges(0, "b")
  assert_eq(incident.length(), 2)
  assert_eq(try! doc.edge_at(incident[1]).source, "b")
  assert_eq(index.incident_hyperedges(0, "b").length(), 1)
  let address = index.graph_address("inner").unwrap()
  address.steps.clear()
  assert_eq(index.graph_address("inner").unwrap().steps.length(), 1)
  assert_true(
    try {
      let _ = doc.graph_at(GraphAddress::root(-1))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = doc.graph_at(GraphAddress::root(0).child(EdgeGraph(0)))
      false
    } catch {
      _ => true
    },
  )
}
