///|
test "flat reader preserves parallel edges, self loops and direction" {
  let doc = try! parse(
    "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><graph id='G' edgedefault='directed'><node id='a'/><node id='b'/><edge source='a' target='b'/><edge source='a' target='b' directed='false'/><edge source='a' target='a'/></graph></graphml>",
  )
  assert_eq(doc.graph_count(), 1)
  let graph = doc.graphs[0]
  assert_eq(graph.edges.length(), 3)
  assert_eq(graph.edges[1].effective_direction(graph), Undirected)
}

///|
test "reader validates references, identifier uniqueness and data scope" {
  for
    body in [
      "<node id='a'/><node id='a'/>", "<node id='a'/><edge source='a' target='missing'/>",
      "<node id='a'><data key='d'>yes</data></node>",
    ] {
    let input = "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><key id='d' for='edge' attr.type='string'/><graph edgedefault='directed'>\{body}</graph></graphml>"
    assert_true(
      try {
        let _ = parse(input)
        false
      } catch {
        InvalidGraph(..) => true
        _ => false
      },
    )
  }
}

///|
test "node names can repeat in separate top-level graphs" {
  let graph = "<graph edgedefault='undirected'><node id='0'/></graph>"
  let doc = try! parse(
    "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'>\{graph}\{graph}</graphml>",
  )
  assert_eq(doc.graph_count(), 2)
}
