///|
test "public builder constructors and getters detach arrays and repeatable snapshots" {
  let key = try! @moongraphml.Key::new(
    "label",
    @moongraphml.NodeScope,
    @moongraphml.StringValue,
  )
  key.extra.push({
    namespace_uri: Some("urn:metadata"),
    name: "origin",
    value: "caller",
  })
  let keys = [key]
  let builder = try! @moongraphml.FlatBuilder::new(keys, @moongraphml.Directed)
  keys.clear()
  key.extra.clear()
  try! builder.add_node("api", attributes=[
    ("label", @moongraphml.TextValue("service")),
  ])
  let first = try! builder.finish()
  try! builder.add_node("db")
  try! builder.add_edge("api", "db", id="uses")
  let second = try! builder.finish()
  assert_eq(first.statistics().nodes, 1)
  assert_eq(second.statistics().nodes, 2)
  assert_eq(first.keys()[0].extra.length(), 1)
  let detached_keys = first.keys()
  detached_keys[0].extra.clear()
  let detached_graphs = first.graphs()
  detached_graphs[0].nodes[0].data.clear()
  detached_graphs.clear()
  assert_eq(first.keys()[0].extra.length(), 1)
  assert_eq(first.graphs()[0].nodes[0].data.length(), 1)
  let index = @moongraphml.GraphIndex::new(second)
  let address = index.node_address(0, "api").unwrap()
  address.graph.steps.push(@moongraphml.NodeGraph(999))
  assert_eq(index.node_address(0, "api").unwrap().graph.steps.length(), 0)
  assert_eq(index.incident_edges(0, "api").length(), 1)
}

///|
test "public row import rename merge flat view and roundtrip form one reusable pipeline" {
  let label = try! @moongraphml.Key::new(
    "label",
    @moongraphml.NodeScope,
    @moongraphml.StringValue,
  )
  let weight = try! @moongraphml.Key::new(
    "weight",
    @moongraphml.EdgeScope,
    @moongraphml.Int32,
    default_value=@moongraphml.IntegerValue(7),
  )
  let nodes : Array[@moongraphml.NodeRow] = [
    {
      id: "api",
      attributes: Map([("label", @moongraphml.TextValue("service"))]),
    },
    { id: "db", attributes: Map([]), },
  ]
  let edges : Array[@moongraphml.EdgeRow] = [
    {
      id: Some("uses"),
      source: "api",
      target: "db",
      direction: @moongraphml.Directed,
      attributes: Map([]),
    },
  ]
  let source = try! @moongraphml.from_rows(
    [label, weight],
    nodes,
    edges,
    graph_id="A",
  )
  let renamed = try! source.rename_node(0, "api", "service")
  let renamed = try! renamed.rename_key("weight", "cost")
  assert_eq(source.graphs()[0].edges[0].source, "api")
  assert_eq(renamed.graphs()[0].edges[0].source, "service")
  let flat = try! renamed.flat_graph(@moongraphml.GraphAddress::root(0))
  assert_true(
    flat.edge_rows()[0].attributes.get("cost")
    is Some(@moongraphml.IntegerValue(7)),
  )
  assert_eq(flat.indexed_edges()[0].source, 0)
  assert_true(renamed.equivalent(try! flat.to_document()))
  let other = try! @moongraphml.from_rows([label], [nodes[0]], [], graph_id="B")
  let merged = try! renamed.merge(other, "import_")
  assert_eq(merged.document.graph_count(), 2)
  assert_eq(merged.key_mapping.get("label"), Some("import_label"))
  assert_eq(merged.graph_mapping.get("B"), Some("import_B"))
  assert_eq(merged.imported_roots, [1])
  let encoded = try! @moongraphml.serialize(merged.document)
  assert_true(merged.document.equivalent(try! @moongraphml.parse(encoded)))
}

///|
test "public XML payload and default extension context roundtrip without aliasing" {
  let source = "<g:graphml xmlns:g='http://graphml.graphdrawing.org/xmlns' xmlns:p='urn:shapes'><g:key id='k'><g:default xmlns:m='urn:metadata' m:kind='p:Rectangle'><p:shape xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance' xsi:type='p:Rectangle'/></g:default></g:key><g:data key='k'><xml:note/></g:data></g:graphml>"
  let doc = try! @moongraphml.parse(source)
  let keys = doc.keys()
  assert_eq(keys[0].default_extra[0].value, "p:Rectangle")
  guard keys[0].default_value is Some(@moongraphml.XmlPayload(values)) else {
    abort("missing extension")
  }
  guard values[0] is @moongraphml.Element(element) else {
    abort("missing element")
  }
  assert_eq(element.prefix, Some("p"))
  assert_true(
    element.namespaces.any(fn(binding) {
      binding.prefix == Some("p") && binding.namespace_uri == "urn:shapes"
    }),
  )
  let rebuilt = try! @moongraphml.Document::new(keys, [], data=doc.data())
  keys[0].default_extra.clear()
  keys[0].default_namespaces.clear()
  element.namespaces.clear()
  element.attributes.clear()
  values.clear()
  assert_true(doc.equivalent(rebuilt))
  let encoded = try! @moongraphml.serialize(rebuilt)
  assert_true(encoded.contains("xsi:type=\"p:Rectangle\""))
  assert_true(encoded.contains("<xml:note"))
  assert_true(rebuilt.equivalent(try! @moongraphml.parse(encoded)))
}
