///|
test "hyperedges preserve endpoint direction, optional ids and nested graphs" {
  let input = "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><graph edgedefault='directed'><node id='a'><port name='p'/></node><node id='b'/><hyperedge id='bus'><endpoint id='e0' node='a' port='p' type='out'/><endpoint node='b' type='in'/><graph edgedefault='undirected'><node id='detail'/></graph></hyperedge></graph></graphml>"
  let doc = try! parse(input)
  let bus = doc.graphs[0].hyperedges[0]
  assert_eq(bus.endpoints.length(), 2)
  assert_eq(bus.endpoints[0].kind, Out)
  assert_true(bus.graph is Some(_))
}

///|
test "missing endpoints, duplicate ids and invalid direction are diagnosed" {
  for
    endpoints in [
      "<endpoint node='missing'/>", "<endpoint id='e' node='a'/><endpoint id='e' node='a'/>",
      "<endpoint node='a' type='bad'/>",
    ] {
    let input = "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><graph edgedefault='directed'><node id='a'/><hyperedge>\{endpoints}</hyperedge></graph></graphml>"
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
test "endpoint allowance rejects expansion above configured bound" {
  let input = "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><graph edgedefault='directed'><node id='a'/><hyperedge><endpoint node='a'/><endpoint node='a'/></hyperedge></graph></graphml>"
  let limits = { ..Limits::default(), endpoints: 1, }
  assert_true(
    try {
      let _ = parse(input, limits~)
      false
    } catch {
      LimitExceeded(..) => true
      _ => false
    },
  )
}
