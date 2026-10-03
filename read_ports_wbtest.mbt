///|
test "hierarchical ports resolve within their node" {
  let doc = try! parse(
    "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><graph edgedefault='undirected'><node id='a'><port name='switch'><port name='eth0'/></port></node><node id='b'><port name='eth0'/></node><edge source='a' target='b' sourceport='eth0' targetport='eth0'/></graph></graphml>",
  )
  assert_eq(doc.graphs[0].nodes[0].ports[0].ports[0].name, "eth0")
}

///|
test "duplicate and missing ports fail and port budgets apply" {
  for
    body in [
      "<node id='a'><port name='x'/><port name='x'/></node>", "<node id='a'/><edge source='a' target='a' sourceport='x'/>",
    ] {
    let input = "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><graph edgedefault='directed'>\{body}</graph></graphml>"
    assert_true(
      try {
        let _ = parse(input)
        false
      } catch {
        _ => true
      },
    )
  }
  let limits = { ..Limits::default(), ports: 0, }
  assert_true(
    try {
      let _ = parse(
        "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><graph edgedefault='directed'><node id='a'><port name='p'/></node></graph></graphml>",
        limits~,
      )
      false
    } catch {
      LimitExceeded(..) => true
      _ => false
    },
  )
}
