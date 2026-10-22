///|
test "public induced subgraph keeps source order loops parallel edges and directions" {
  let doc = try! @moongraphml.parse(
    "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><key id='w' for='edge' attr.type='long'><default>9007199254740993</default></key><graph id='G' edgedefault='directed'><node id='a'/><node id='b'/><node id='c'/><node id='isolated'/><edge id='ab' source='a' target='b'/><edge id='ba' source='b' target='a' directed='false'/><edge id='loop' source='a' target='a'/><edge id='parallel' source='a' target='b'><data key='w'>0</data></edge><edge id='bc' source='b' target='c'/></graph></graphml>",
  )
  let flat = try! doc.flat_graph(@moongraphml.GraphAddress::root(0))
  let selection = ["isolated", "b", "a"]
  let result = try! flat.induced_subgraph(selection)
  selection.clear()
  let graph = result.graphs()[0]
  assert_eq(graph.id, Some("G"))
  assert_eq(graph.nodes.map(fn(node) { node.id }), ["a", "b", "isolated"])
  assert_eq(graph.edges.map(fn(edge) { edge.id }), [
    Some("ab"),
    Some("ba"),
    Some("loop"),
    Some("parallel"),
  ])
  assert_eq(graph.edges[1].effective_direction(graph), @moongraphml.Undirected)
  let rows = try! result
    .flat_graph(@moongraphml.GraphAddress::root(0))
    .edge_rows()
  assert_true(
    rows[0].attributes.get("w")
    is Some(@moongraphml.LongValue(9007199254740993L)),
  )
  assert_true(rows[3].attributes.get("w") is Some(@moongraphml.LongValue(0L)))
  assert_eq(doc.statistics().nodes, 4)
  assert_eq(doc.statistics().edges, 5)
  assert_true(
    result.equivalent(try! @moongraphml.parse(@moongraphml.serialize(result))),
  )
}

///|
test "public induced subgraph retains XML contexts and clears stale topology hints" {
  let doc = try! @moongraphml.parse(
    "<g:graphml xmlns:g='http://graphml.graphdrawing.org/xmlns' xmlns:p='urn:payload' xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance'><g:key id='k'><g:default xsi:type='p:Default'><p:value>fallback</p:value></g:default></g:key><g:graph id='G' edgedefault='directed' parse.nodes='2' parse.edges='1' parse.nodeids='canonical' parse.edgeids='canonical' parse.order='adjacencylist' p:origin='inventory'><g:desc>topology</g:desc><g:data key='k'><p:value xsi:type='p:Kind'>graph</p:value></g:data><g:node id='n0'/><g:node id='n1' parse.indegree='1' parse.outdegree='0' p:parse.indegree='custom'><g:data key='k'><p:value xsi:type='p:Kind'>node</p:value></g:data></g:node><g:edge id='e0' source='n0' target='n1'/></g:graph></g:graphml>",
  )
  let result = try! doc
    .flat_graph(@moongraphml.GraphAddress::root(0))
    .induced_subgraph(["n1"])
  let graph = result.graphs()[0]
  let hints = try! graph.parse_info()
  assert_true(
    hints.nodes is None &&
    hints.edges is None &&
    hints.node_ids is None &&
    hints.edge_ids is None,
  )
  assert_true(hints.max_in_degree is None && hints.max_out_degree is None)
  try! hints.check_flat_counts(graph)
  let degree = try! graph.nodes[0].degree_hints()
  assert_true(degree.in_degree is None && degree.out_degree is None)
  assert_eq(graph.nodes[0].extra.length(), 1)
  assert_eq(graph.nodes[0].extra[0].namespace_uri, Some("urn:payload"))
  assert_eq(graph.extra[0].value, "inventory")
  assert_eq(graph.description, Some("topology"))
  let output = try! @moongraphml.serialize(result)
  assert_true(output.contains("xsi:type=\"p:Kind\""))
  assert_true(result.equivalent(try! @moongraphml.parse(output)))
  graph.nodes[0].data.clear()
  graph.namespaces.clear()
  let keys = result.keys()
  keys[0].default_namespaces.clear()
  assert_eq(result.graphs()[0].nodes[0].data.length(), 1)
  assert_true(result.keys()[0].default_namespaces.length() > 0)
  assert_eq(doc.graphs()[0].nodes.length(), 2)
  assert_eq(try! doc.graphs()[0].parse_info().nodes.unwrap().decimal(), "2")
}

///|
test "public induced subgraph empty all unknown duplicate and configured limits" {
  let builder = try! @moongraphml.FlatBuilder::new([], @moongraphml.Directed)
  try! builder.add_node("a")
  try! builder.add_edge("a", "a")
  let doc = try! builder.finish()
  let flat = try! doc.flat_graph(@moongraphml.GraphAddress::root(0))
  assert_true(doc.equivalent(try! flat.induced_subgraph(["a"])))
  let empty = try! flat.induced_subgraph([])
  assert_eq(empty.graph_count(), 1)
  assert_eq(empty.statistics().nodes, 0)
  assert_eq(empty.statistics().edges, 0)
  for selection in [["missing"], ["a", "a"], ["a", "missing"]] {
    assert_true(
      try {
        let _ = flat.induced_subgraph(selection)
        false
      } catch {
        @moongraphml.InvalidGraph(path~, ..) => path == "subgraph.nodes"
        _ => false
      },
    )
  }
  for
    (limits, expected) in [
      ({ ..@moongraphml.Limits::default(), nodes: 0, }, "nodes"),
      ({ ..@moongraphml.Limits::default(), edges: 0, }, "edges"),
      ({ ..@moongraphml.Limits::default(), graphs: 0, }, "graphs"),
      ({ ..@moongraphml.Limits::default(), output_bytes: 0, }, "output_bytes"),
    ] {
    assert_true(
      try {
        let _ = flat.induced_subgraph(["a"], limits~)
        false
      } catch {
        @moongraphml.LimitExceeded(resource~, ..) => resource == expected
        _ => false
      },
    )
  }
  assert_true(
    try {
      let _ = flat.induced_subgraph([], limits={
        ..@moongraphml.Limits::default(),
        nodes: -1,
      })
      false
    } catch {
      @moongraphml.InvalidGraph(path~, ..) => path == "limits"
      _ => false
    },
  )
}

///|
test "flat projection still rejects advanced structures before the new adapters" {
  for
    xml in [
      "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><graph edgedefault='directed'><node id='a'><port name='p'/></node></graph></graphml>",
      "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><graph edgedefault='directed'><node id='a'><graph edgedefault='directed'/></node></graph></graphml>",
      "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><graph edgedefault='directed'><node id='a'/><hyperedge><endpoint node='a'/></hyperedge></graph></graphml>",
    ] {
    let doc = try! @moongraphml.parse(xml)
    assert_true(
      try {
        let _ = doc.flat_graph(@moongraphml.GraphAddress::root(0))
        false
      } catch {
        @moongraphml.InvalidGraph(..) => true
        _ => false
      },
    )
  }
}
