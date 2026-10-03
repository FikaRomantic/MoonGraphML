///|
test "statistics distinguish semantic direction from explicit override spelling" {
  let doc = try! parse(
    "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><graph edgedefault=\"undirected\"><node id=\"a\"><port name=\"p\"/><graph edgedefault=\"directed\"><node id=\"b\"/></graph></node><edge source=\"a\" target=\"b\"/><edge source=\"b\" target=\"a\"/><edge source=\"b\" target=\"b\" directed=\"true\"/><hyperedge><endpoint node=\"a\"/><endpoint node=\"b\"/></hyperedge></graph></graphml>",
  )
  let stats = doc.statistics()
  assert_eq(stats.graphs, 2)
  assert_eq(stats.nodes, 2)
  assert_eq(stats.edges, 3)
  assert_eq(stats.hyperedges, 1)
  assert_eq(stats.endpoints, 2)
  assert_eq(stats.ports, 1)
  assert_eq(stats.max_graph_depth, 2)
  assert_true(stats.has_mixed_direction)
  assert_true(stats.has_parallel_edges)
  assert_true(stats.has_self_loops)
  assert_false(stats.has_locators)
}
