///|
test "constructor and getters detach mutable arrays deeply" {
  let graph = Graph::new(Directed)
  let node = Node::new("a")
  node.ports.push(Port::new("p"))
  graph.nodes.push(node)
  let doc = try! Document::new([], [graph])
  node.ports.push(Port::new("q"))
  graph.nodes.push(Node::new("b"))
  let detached = doc.graphs()
  assert_eq(detached[0].nodes.length(), 1)
  assert_eq(detached[0].nodes[0].ports.length(), 1)
  detached[0].nodes[0].ports.clear()
  detached.clear()
  assert_eq(doc.graphs()[0].nodes[0].ports.length(), 1)
}

///|
test "key default metadata cannot be silently lost when no default exists" {
  let key = try! Key::new("k", NodeScope, StringValue)
  let with_extra = {
    ..key,
    default_extra: [
      { namespace_uri: Some("urn:metadata"), name: "kind", value: "label", },
    ],
  }
  let with_namespaces = {
    ..key,
    default_namespaces: [{ prefix: Some("m"), namespace_uri: "urn:metadata", }],
  }
  for malformed in [with_extra, with_namespaces] {
    assert_true(
      try {
        let _ = Document::new([malformed], [])
        false
      } catch {
        InvalidGraph(path="key.default", ..) => true
        _ => false
      },
    )
  }
}

///|
test "constructor rejects mismatched types and locator data loss" {
  let key = try! Key::new("k", NodeScope, Int32)
  let node = Node::new("a")
  node.data.push(Datum::new("k", TextValue("12")))
  let graph = Graph::new(Directed)
  graph.nodes.push(node)
  assert_true(
    try {
      let _ = Document::new([key], [graph])
      false
    } catch {
      _ => true
    },
  )
  let located = {
    ..graph,
    locator: Some({
      href: "file:///never-read",
      link_type: None,
      extra: [],
      namespaces: [],
    }),
  }
  assert_true(
    try {
      let _ = Document::new([], [located])
      false
    } catch {
      _ => true
    },
  )
}

///|
test "constructor rejects cyclic graph and port models without stack overflow" {
  let graph = Graph::new(Directed)
  graph.nodes.push({ ..Node::new("a"), graph: Some(graph), })
  assert_true(
    try {
      let _ = Document::new([], [graph], limits={
        ..Limits::default(),
        xml_depth: 10,
      })
      false
    } catch {
      LimitExceeded(..) => true
      _ => false
    },
  )
  let port = Port::new("p")
  port.ports.push(port)
  let flat = Graph::new(Directed)
  let node = Node::new("a")
  node.ports.push(port)
  flat.nodes.push(node)
  assert_true(
    try {
      let _ = Document::new([], [flat], limits={
        ..Limits::default(),
        xml_depth: 10,
      })
      false
    } catch {
      LimitExceeded(..) => true
      _ => false
    },
  )
}
