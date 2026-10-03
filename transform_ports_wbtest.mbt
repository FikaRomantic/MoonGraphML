///|
test "port rename preserves hierarchy and updates all endpoint references" {
  let doc = try! parse(
    "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><graph edgedefault=\"directed\"><node id=\"a\"><port name=\"outer\"><port name=\"old\"/></port></node><node id=\"b\"><port name=\"old\"/></node><edge source=\"a\" target=\"b\" sourceport=\"old\" targetport=\"old\"/><hyperedge><endpoint node=\"a\" port=\"old\"/></hyperedge></graph></graphml>",
  )
  let changed = try! doc.rename_port(0, "a", "old", "new")
  let graph = changed.graphs()[0]
  assert_eq(graph.nodes[0].ports[0].ports[0].name, "new")
  assert_eq(graph.edges[0].source_port, Some("new"))
  assert_eq(graph.edges[0].target_port, Some("old"))
  assert_eq(graph.hyperedges[0].endpoints[0].port, Some("new"))
  assert_true(
    try {
      let _ = doc.rename_port(0, "a", "old", "outer")
      false
    } catch {
      _ => true
    },
  )
  assert_eq(doc.graphs()[0].edges[0].source_port, Some("old"))
}
