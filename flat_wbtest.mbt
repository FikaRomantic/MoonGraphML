///|
test "typed rows preserve mixed direction loops and parallel edges" {
  let keys = [
    try! Key::new("weight", EdgeScope, Float64, default_value=DoubleValue(1.5)),
  ]
  let doc = try! from_rows(
    keys,
    [{ id: "a", attributes: Map([]), }, { id: "b", attributes: Map([]), }],
    [
      {
        id: Some("1"),
        source: "a",
        target: "b",
        direction: Directed,
        attributes: Map([]),
      },
      {
        id: Some("2"),
        source: "a",
        target: "b",
        direction: Undirected,
        attributes: Map([]),
      },
      {
        id: None,
        source: "b",
        target: "b",
        direction: Directed,
        attributes: Map([]),
      },
    ],
  )
  let flat = try! doc.flat_graph(GraphAddress::root(0))
  assert_eq(flat.indexed_edges().length(), 3)
  assert_eq(flat.indexed_edges()[2].source, 1)
  assert_eq(flat.indexed_edges()[1].direction, Undirected)
  let rows = try! flat.edge_rows()
  assert_true(rows[0].attributes.get("weight") is Some(DoubleValue(1.5)))
  assert_eq(try! flat.edge_rows(use_defaults=false)[0].attributes.length(), 0)
  assert_eq(
    try! from_rows(keys, flat.node_rows(), rows).graphs()[0].edges.length(),
    3,
  )
}

///|
test "flat adapter rejects lossy advanced conversion and unknown table keys" {
  let graph = Graph::new(Directed)
  let node = Node::new("a")
  node.ports.push(Port::new("p"))
  graph.nodes.push(node)
  let doc = try! Document::new([], [graph])
  assert_true(
    try {
      let _ = doc.flat_graph(GraphAddress::root(0))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = from_rows(
        [],
        [{ id: "a", attributes: Map([("missing", TextValue("x"))]), }],
        [],
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "sparse tables handle 4096 declarations without materializing absent values" {
  let keys = []
  for i = 0; i < 4096; i = i + 1 {
    keys.push(try! Key::new("k\{i}", All, Int32))
  }
  let rows = []
  for i = 0; i < 100; i = i + 1 {
    rows.push({
      id: "n\{i}",
      attributes: if i % 3 == 0 {
        Map([])
      } else {
        Map([("k4095", IntegerValue(i)), ("k0", IntegerValue(-i))])
      },
    })
  }
  let doc = try! from_rows(keys, rows, [
    {
      id: Some("e"),
      source: "n0",
      target: "n1",
      direction: Directed,
      attributes: Map([("k4095", IntegerValue(10))]),
    },
  ])
  let flat = try! doc.flat_graph(GraphAddress::root(0))
  let recovered = try! flat.node_rows()
  assert_eq(recovered.length(), 100)
  assert_eq(recovered[0].attributes.length(), 0)
  assert_eq(recovered[1].attributes.length(), 2)
  assert_true(recovered[1].attributes.get("k4095") is Some(IntegerValue(1)))
  assert_eq(try! flat.edge_rows()[0].attributes.length(), 1)
  assert_eq(flat.graph().nodes[1].data[0].key, "k0")
  assert_eq(flat.graph().nodes[1].data[1].key, "k4095")
}

///|
test "compiled table defaults respect scope explicit overrides and opt out" {
  let keys = [
    try! Key::new("number", NodeScope, Int32, default_value=IntegerValue(7)),
    try! Key::new("weight", EdgeScope, Float64, default_value=DoubleValue(2.5)),
    try! Key::new("label", All, StringValue, default_value=TextValue("")),
  ]
  let doc = try! from_rows(
    keys,
    [
      { id: "a", attributes: Map([("number", IntegerValue(0))]), },
      { id: "b", attributes: Map([]), },
    ],
    [
      {
        id: None,
        source: "a",
        target: "b",
        direction: Directed,
        attributes: Map([("weight", DoubleValue(0.0))]),
      },
    ],
  )
  let flat = try! doc.flat_graph(GraphAddress::root(0))
  let nodes = try! flat.node_rows()
  assert_true(nodes[0].attributes.get("number") is Some(IntegerValue(0)))
  assert_true(nodes[1].attributes.get("number") is Some(IntegerValue(7)))
  assert_true(nodes[1].attributes.get("label") is Some(TextValue("")))
  assert_true(!nodes[0].attributes.contains("weight"))
  let edges = try! flat.edge_rows()
  assert_true(edges[0].attributes.get("weight") is Some(DoubleValue(0.0)))
  assert_true(!edges[0].attributes.contains("number"))
  assert_eq(try! flat.node_rows(use_defaults=false)[1].attributes.length(), 0)
  assert_eq(try! flat.edge_rows(use_defaults=false)[0].attributes.length(), 1)
}

///|
test "XML defaults reject scalar rows only when applicable and not overridden" {
  let doc = try! parse(
    "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><key id='payload' for='node'><default><e:value xmlns:e='urn:test'>xml</e:value></default></key><graph edgedefault='directed'><node id='a'><data key='payload'>plain</data></node><node id='b'/><edge source='a' target='b'/></graph></graphml>",
  )
  let flat = try! doc.flat_graph(GraphAddress::root(0))
  assert_true(
    try {
      let _ = flat.node_rows()
      false
    } catch {
      Unsupported(..) => true
      _ => false
    },
  )
  let authored = try! flat.node_rows(use_defaults=false)
  assert_true(authored[0].attributes.get("payload") is Some(TextValue("plain")))
  assert_eq(authored[1].attributes.length(), 0)
  assert_eq(try! flat.edge_rows()[0].attributes.length(), 0)
  let all_overridden = try! from_rows(
    doc.keys(),
    [{ id: "a", attributes: Map([("payload", TextValue("plain"))]), }],
    [],
  )
  let overridden_flat = try! all_overridden.flat_graph(GraphAddress::root(0))
  assert_eq(try! overridden_flat.node_rows()[0].attributes.length(), 1)
}

///|
test "row map insertion order does not change declaration ordered output" {
  let keys = [
    try! Key::new("z", All, Int32),
    try! Key::new("a", All, Int32),
    try! Key::new("m", All, Int32),
  ]
  let left = Map([
    ("m", IntegerValue(3)),
    ("z", IntegerValue(1)),
    ("a", IntegerValue(2)),
  ])
  let right = Map([
    ("a", IntegerValue(2)),
    ("m", IntegerValue(3)),
    ("z", IntegerValue(1)),
  ])
  let first = try! from_rows(keys, [{ id: "n", attributes: left, }], [])
  let second = try! from_rows(keys, [{ id: "n", attributes: right, }], [])
  assert_eq(try! serialize(first), try! serialize(second))
  let data = first.graphs()[0].nodes[0].data
  assert_eq(data[0].key, "z")
  assert_eq(data[1].key, "a")
  assert_eq(data[2].key, "m")
  for
    values in [
      Map([("missing", IntegerValue(1))]),
      Map([("z", DoubleValue(1.0))]),
    ] {
    assert_true(
      try {
        let _ = from_rows(keys, [{ id: "n", attributes: values, }], [])
        false
      } catch {
        InvalidGraph(..) => true
        _ => false
      },
    )
  }
  assert_true(
    try {
      let _ = from_rows(
        [Key::new("node-only", NodeScope, Int32)],
        [{ id: "n", attributes: Map([]), }],
        [
          {
            id: None,
            source: "n",
            target: "n",
            direction: Directed,
            attributes: Map([("node-only", IntegerValue(1))]),
          },
        ],
      )
      false
    } catch {
      InvalidGraph(..) => true
      _ => false
    },
  )
}

///|
test "row construction checks configured collection budgets before materialization" {
  let keys = [try! Key::new("k", All, Int32)]
  let nodes = [
    { id: "a", attributes: Map([]), },
    { id: "b", attributes: Map([]), },
  ]
  let edges = [
    {
      id: None,
      source: "a",
      target: "b",
      direction: Directed,
      attributes: Map([]),
    },
    {
      id: None,
      source: "b",
      target: "a",
      direction: Directed,
      attributes: Map([]),
    },
  ]
  for
    (limits, expected) in [
      ({ ..Limits::default(), keys: 0, }, "keys"),
      ({ ..Limits::default(), graphs: 0, }, "graphs"),
      ({ ..Limits::default(), nodes: 1, }, "nodes"),
      ({ ..Limits::default(), edges: 1, }, "edges"),
    ] {
    assert_true(
      try {
        let _ = from_rows(keys, nodes, edges, limits~)
        false
      } catch {
        LimitExceeded(resource~, ..) => resource == expected
        _ => false
      },
    )
  }
  assert_true(
    try {
      let _ = from_rows(keys, nodes, edges, limits={
        ..Limits::default(),
        keys: -1,
      })
      false
    } catch {
      InvalidGraph(path~, ..) => path == "limits"
      _ => false
    },
  )
  assert_eq(
    try! from_rows(keys, nodes, edges, limits={
      ..Limits::default(),
      keys: 1,
      graphs: 1,
      nodes: 2,
      edges: 2,
    }).statistics().edges,
    2,
  )
}
