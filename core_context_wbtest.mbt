///|
test "core xsi type contexts survive roundtrip transforms and detached getters" {
  let input = "<graphml xmlns='http://graphml.graphdrawing.org/xmlns' xmlns:g='http://graphml.graphdrawing.org/xmlns' xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance' xsi:type='g:graphml.type'><key id='k' attr.type='string' xsi:type='g:key.type'/><graph id='G' edgedefault='directed' xsi:type='g:graph.type'><node id='a' xsi:type='g:node.type'><port name='p' xsi:type='g:port.type'/><data key='k' xsi:type='g:data.type'>text</data></node><edge id='e' source='a' target='a' sourceport='p' xsi:type='g:edge.type'/><hyperedge id='h' xsi:type='g:hyperedge.type'><endpoint node='a' port='p' xsi:type='g:endpoint.type'/></hyperedge></graph></graphml>"
  let doc = try! parse(input)
  let baseline = try! serialize(doc)
  assert_true(doc.equivalent(try! parse(baseline)))
  doc.namespace_bindings().clear()
  let keys = doc.keys()
  keys[0].namespaces.clear()
  let graphs = doc.graphs()
  graphs[0].namespaces.clear()
  graphs[0].nodes[0].namespaces.clear()
  graphs[0].nodes[0].ports[0].namespaces.clear()
  graphs[0].nodes[0].data[0].namespaces.clear()
  graphs[0].edges[0].namespaces.clear()
  graphs[0].hyperedges[0].namespaces.clear()
  graphs[0].hyperedges[0].endpoints[0].namespaces.clear()
  assert_eq(try! serialize(doc), baseline)
  let renamed = try! doc.rename_node(0, "a", "b")
  assert_true(try! serialize(renamed).contains("xsi:type=\"g:graphml.type\""))
  assert_eq(
    namespace_uri_for(renamed.namespace_bindings(), Some("g")),
    Some(GRAPHML_URI),
  )
  assert_true(renamed.equivalent(try! parse(serialize(renamed))))
  let changed_graphs = doc.graphs()
  set_namespace_binding(
    changed_graphs[0].nodes[0].namespaces,
    Some("g"),
    "urn:different-type-context",
  )
  let changed = try! Document::new(
    doc.keys(),
    changed_graphs,
    extra=doc.extra_attributes(),
    namespaces=doc.namespace_bindings(),
  )
  assert_false(doc.equivalent(changed))
}

///|
test "resolving a text default carries context without copying default wrapper attributes" {
  let doc = try! parse(
    "<g:graphml xmlns:g='http://graphml.graphdrawing.org/xmlns' xmlns:p='urn:type' xmlns:m='urn:meta'><g:key id='k' for='node'><g:default m:kind='p:Thing'>p:Thing</g:default></g:key><g:graph edgedefault='directed'><g:node id='n'/></g:graph></g:graphml>",
  )
  let attributes = try! Attributes::new(doc, NodeScope, [])
  let data = attributes.resolved()
  assert_eq(data.length(), 1)
  assert_eq(namespace_uri_for(data[0].namespaces, Some("p")), Some("urn:type"))
  assert_true(data[0].extra.is_empty())
  data[0].namespaces.clear()
  assert_eq(
    namespace_uri_for(attributes.resolved()[0].namespaces, Some("p")),
    Some("urn:type"),
  )
}

///|
test "merging root contexts rejects prefixed and unknowable unprefixed conflicts" {
  for value in ["p:Thing", "Thing"] {
    let left = try! parse(
      "<g:graphml xmlns:g='http://graphml.graphdrawing.org/xmlns' xmlns='urn:left' xmlns:p='urn:left' xmlns:m='urn:meta' m:kind='\{value}'/>",
    )
    let right = try! parse(
      "<g:graphml xmlns:g='http://graphml.graphdrawing.org/xmlns' xmlns='urn:right' xmlns:p='urn:right' xmlns:m='urn:meta' m:kind='\{value}'/>",
    )
    assert_true(
      try {
        let _ = left.merge(right, "import_")
        false
      } catch {
        InvalidGraph(path="merge.graphml", ..) => true
        _ => false
      },
    )
  }
  let empty_root = try! parse(
    "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><graph id='a' edgedefault='directed'/></graphml>",
  )
  let right = try! parse(
    "<g:graphml xmlns:g='http://graphml.graphdrawing.org/xmlns' xmlns='urn:type' xmlns:m='urn:meta' m:kind='Thing'><g:graph id='b' edgedefault='directed'/></g:graphml>",
  )
  let merged = try! empty_root.merge(right, "import_")
  assert_eq(
    namespace_uri_for(merged.document.namespace_bindings(), None),
    Some("urn:type"),
  )
  assert_eq(merged.document.graph_count(), 2)
  assert_true(
    merged.document.equivalent(try! parse(serialize(merged.document))),
  )
}

///|
test "serializer enforces attribute namespace and aggregate direct text ceilings" {
  let doc = try! parse(
    "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><key id='k'/><data key='k'>123456789012345678901234567890123456789012345678901234567890</data></graphml>",
  )
  assert_true(
    try {
      let _ = serialize(doc, limits={ ..Limits::default(), text_bytes: 50, })
      false
    } catch {
      LimitExceeded(resource="text_bytes", ..) => true
      _ => false
    },
  )
  assert_true(
    try {
      let _ = serialize(doc, limits={
        ..Limits::default(),
        attributes_per_element: 0,
      })
      false
    } catch {
      LimitExceeded(resource="attributes_per_element", ..) => true
      _ => false
    },
  )
  let output = Output::new({ ..Limits::default(), text_bytes: 5, })
  output.start("root", [])
  output.escaped("123", false)
  output.start("child", [])
  output.escaped("12345", false)
  output.end("child")
  assert_true(
    try {
      output.escaped("456", false)
      false
    } catch {
      LimitExceeded(resource="text_bytes", ..) => true
      _ => false
    },
  )
}
