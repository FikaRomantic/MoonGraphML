///|
test "parent edges can reference nodes inside child graphs" {
  let doc = try! parse(
    "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><graph id='root' edgedefault='directed'><node id='group'><graph id='child' edgedefault='undirected'><node id='inner'/></graph></node><node id='outer'/><edge source='inner' target='outer'/></graph></graphml>",
  )
  assert_true(doc.graphs[0].nodes[0].graph is Some(_))
}

///|
test "child graphs cannot reference outside nodes and ids are scoped to ancestor graph" {
  for
    child in [
      "<node id='inner'/><edge source='inner' target='outer'/>", "<node id='outer'/>",
    ] {
    let input = "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><graph edgedefault='directed'><node id='group'><graph edgedefault='directed'>\{child}</graph></node><node id='outer'/></graph></graphml>"
    assert_true(
      try {
        let _ = parse(input)
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "only one final nested graph is permitted per node and edge" {
  let nested = "<graph edgedefault='directed'/>"
  let input = "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><graph edgedefault='directed'><node id='n'>\{nested}\{nested}</node></graph></graphml>"
  assert_true(
    try {
      let _ = parse(input)
      false
    } catch {
      _ => true
    },
  )
}
