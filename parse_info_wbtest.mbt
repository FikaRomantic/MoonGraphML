///|
test "parse info handles arbitrary-size integers without narrowing" {
  assert_eq(try! CountHint::parse(" +00012 ").decimal(), "12")
  assert_eq(try! CountHint::parse("-000").decimal(), "0")
  assert_eq(try! CountHint::parse("999999999999999999999999").to_int64(), None)
  assert_true(
    try {
      let _ = CountHint::parse("-1")
      false
    } catch {
      _ => true
    },
  )
  let doc = try! parse(
    "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><graph edgedefault=\"directed\" parse.nodes=\"1\" parse.edges=\"0\" parse.nodeids=\"canonical\" parse.order=\"adjacencylist\"><node id=\"n0\" parse.indegree=\"0\"/></graph></graphml>",
  )
  let graph = doc.graphs()[0]
  let hints = try! graph.parse_info()
  try! hints.check_flat_counts(graph)
  assert_eq(hints.order, Some(AdjacencyList))
  assert_eq(
    try! parse(serialize(doc)).graphs()[0].parse_info().order,
    Some(NodesFirst),
  )
  assert_true(doc.equivalent(try! parse(serialize(doc))))
}

///|
test "advisory count consistency is opt-in but malformed hint types fail" {
  let doc = try! parse(
    "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><graph edgedefault=\"directed\" parse.nodes=\"99\"><node id=\"a\"/></graph></graphml>",
  )
  let graph = doc.graphs()[0]
  assert_true(
    try {
      graph.parse_info().check_flat_counts(graph)
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = parse(
        "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><graph edgedefault=\"directed\" parse.order=\"bad\"/></graphml>",
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "port uniqueness covers nested node descendants but reference scope stays local" {
  assert_true(
    try {
      let _ = parse(
        "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><graph edgedefault=\"directed\"><node id=\"outer\"><graph edgedefault=\"directed\"><node id=\"a\"><port name=\"p\"/></node><node id=\"b\"><port name=\"p\"/></node></graph></node></graph></graphml>",
      )
      false
    } catch {
      _ => true
    },
  )
  let doc = try! parse(
    "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><graph edgedefault=\"directed\"><node id=\"a\"><port name=\"p\"/></node><node id=\"b\"><port name=\"p\"/></node></graph></graphml>",
  )
  assert_eq(doc.statistics().ports, 2)
}
