///|
fn csr_fixture() -> @moongraphml.FlatGraph raise @moongraphml.GraphError {
  let doc = @moongraphml.parse(
    "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><graph edgedefault='directed'><node id='a'/><node id='b'/><node id='c'/><node id='isolated'/><edge source='a' target='b'/><edge source='b' target='a' directed='false'/><edge source='a' target='a' directed='false'/><edge source='b' target='a'/><edge source='a' target='b'/><edge source='c' target='c'/></graph></graphml>",
  )
  doc.flat_graph(@moongraphml.GraphAddress::root(0))
}

///|
test "public CSR outgoing keeps mixed direction parallel edges and isolated rows" {
  let flat = try! csr_fixture()
  let csr = try! flat.to_csr()
  assert_eq(csr.node_count(), 4)
  assert_eq(csr.arc_count(), 7)
  assert_eq(csr.node_ids(), ["a", "b", "c", "isolated"])
  assert_eq(csr.indptr(), [0, 4, 6, 7, 7])
  assert_eq(csr.indices(), [1, 1, 0, 1, 0, 0, 2])
  assert_eq(csr.edge_indices(), [0, 1, 2, 4, 1, 3, 5])
  assert_eq(csr.reversed(), [false, true, false, false, false, false, false])
  assert_eq(csr.node_index("isolated"), Some(3))
  assert_eq(csr.node_index("absent"), None)
  assert_eq(try! csr.row(3).length(), 0)
  let first = try! csr.row(0)
  assert_eq(first[1], { target: 1, edge_index: 1, reversed: true, })
  let edges = flat.graph().edges
  assert_eq(edges[first[1].edge_index].source, "b")
}

///|
test "public CSR incoming transposes only directed arcs and retains undirected loops once" {
  let csr = try! csr_fixture().to_csr(orientation=@moongraphml.Incoming)
  assert_eq(csr.indptr(), [0, 3, 6, 7, 7])
  assert_eq(csr.indices(), [1, 0, 1, 0, 0, 0, 2])
  assert_eq(csr.edge_indices(), [1, 2, 3, 0, 1, 4, 5])
  assert_eq(csr.reversed(), [true, false, true, true, false, true, true])
  assert_eq(try! csr.row(2).length(), 1)
}

///|
test "public CSR getters are detached and budgets fail before allocation" {
  let flat = try! csr_fixture()
  let csr = try! flat.to_csr(max_arcs=7)
  csr.node_ids().clear()
  csr.indptr().clear()
  csr.indices().clear()
  csr.edge_indices().clear()
  csr.reversed().clear()
  try! csr.row(0).clear()
  assert_eq(csr.node_count(), 4)
  assert_eq(csr.arc_count(), 7)
  assert_eq(csr.node_index("b"), Some(1))
  assert_eq(try! csr.row(0).length(), 4)
  for ceiling in [0, 6] {
    assert_true(
      try {
        let _ = flat.to_csr(max_arcs=ceiling)
        false
      } catch {
        @moongraphml.LimitExceeded(resource~, limit~) =>
          resource == "csr.arcs" && limit == ceiling
        _ => false
      },
    )
  }
  assert_true(
    try {
      let _ = flat.to_csr(max_arcs=-1)
      false
    } catch {
      @moongraphml.InvalidGraph(path~, ..) => path == "csr.max_arcs"
      _ => false
    },
  )
  for index in [-1, 4, 2147483647] {
    assert_true(
      try {
        let _ = csr.row(index)
        false
      } catch {
        @moongraphml.InvalidGraph(path~, ..) => path == "csr.row"
        _ => false
      },
    )
  }
}

///|
test "public CSR empty and edgeless graphs have valid offsets" {
  let empty_doc = try! @moongraphml.from_rows([], [], [])
  let empty = try! empty_doc
    .flat_graph(@moongraphml.GraphAddress::root(0))
    .to_csr(max_arcs=0)
  assert_eq(empty.indptr(), [0])
  assert_eq(empty.node_count(), 0)
  assert_eq(empty.arc_count(), 0)
  let doc = try! @moongraphml.from_rows(
    [],
    [
      { id: "孤立🌙", attributes: Map([]), },
      { id: "b", attributes: Map([]), },
    ],
    [],
  )
  let csr = try! doc
    .flat_graph(@moongraphml.GraphAddress::root(0))
    .to_csr(max_arcs=0)
  assert_eq(csr.node_index("孤立🌙"), Some(0))
  assert_eq(csr.indptr(), [0, 0, 0])
  assert_eq(try! csr.row(0).length(), 0)
}

///|
test "public CSR agrees with independent edge scan for generated subsets and directions" {
  for seed = 0; seed < 24; seed = seed + 1 {
    let builder = try! @moongraphml.FlatBuilder::new(
      [],
      if seed % 2 == 0 {
        @moongraphml.Directed
      } else {
        @moongraphml.Undirected
      },
    )
    for i = 0; i < 5; i = i + 1 {
      try! builder.add_node("n\{i}")
    }
    for i = 0; i < 12; i = i + 1 {
      try! builder.add_edge(
        "n\{(i + seed) % 5}",
        "n\{(i * 3 + seed / 2) % 5}",
        directed=i % 3 != 0,
      )
    }
    let original = try! builder.finish()
    let selection = []
    for i = 4; i >= 0; i = i - 1 {
      if (seed + i) % 3 != 0 {
        selection.push("n\{i}")
      }
    }
    let flat = try! original.flat_graph(@moongraphml.GraphAddress::root(0))
    let subset = try! flat.induced_subgraph(selection)
    let graph = subset.graphs()[0]
    assert_eq(graph.nodes.length(), selection.length())
    assert_eq(
      graph.edges.length(),
      original.graphs()[0].edges
      .filter(fn(edge) {
        selection.contains(edge.source) && selection.contains(edge.target)
      })
      .length(),
    )
    let selected_flat = try! subset.flat_graph(
      @moongraphml.GraphAddress::root(0),
    )
    for orientation in [@moongraphml.Outgoing, @moongraphml.Incoming] {
      let csr = try! selected_flat.to_csr(orientation~)
      let ids = csr.node_ids()
      let indptr = csr.indptr()
      assert_eq(indptr.length(), ids.length() + 1)
      assert_eq(indptr[ids.length()], csr.arc_count())
      for row = 0; row < ids.length(); row = row + 1 {
        let expected : Array[@moongraphml.CsrEntry] = []
        for e = 0; e < graph.edges.length(); e = e + 1 {
          let edge = graph.edges[e]
          if edge.effective_direction(graph) == @moongraphml.Undirected {
            if edge.source == ids[row] {
              expected.push({
                target: csr.node_index(edge.target).unwrap(),
                edge_index: e,
                reversed: false,
              })
            }
            if edge.target == ids[row] && edge.source != edge.target {
              expected.push({
                target: csr.node_index(edge.source).unwrap(),
                edge_index: e,
                reversed: true,
              })
            }
          } else if orientation == @moongraphml.Outgoing &&
            edge.source == ids[row] {
            expected.push({
              target: csr.node_index(edge.target).unwrap(),
              edge_index: e,
              reversed: false,
            })
          } else if orientation == @moongraphml.Incoming &&
            edge.target == ids[row] {
            expected.push({
              target: csr.node_index(edge.source).unwrap(),
              edge_index: e,
              reversed: true,
            })
          }
        }
        assert_eq(try! csr.row(row), expected)
      }
    }
  }
}

///|
test "public adapters handle a sparse 4096-node 16384-edge workload" {
  let builder = try! @moongraphml.FlatBuilder::new([], @moongraphml.Directed)
  for i = 0; i < 4096; i = i + 1 {
    try! builder.add_node("n\{i}")
  }
  for i = 0; i < 16384; i = i + 1 {
    try! builder.add_edge("n\{i % 4096}", "n\{(i + 1) % 4096}")
  }
  let doc = try! builder.finish()
  let flat = try! doc.flat_graph(@moongraphml.GraphAddress::root(0))
  let csr = try! flat.to_csr(max_arcs=16384)
  assert_eq(csr.indptr().length(), 4097)
  assert_eq(csr.arc_count(), 16384)
  assert_eq(try! csr.row(4095).length(), 4)
  assert_eq(try! csr.row(4095)[0].target, 0)
  let selected = []
  for i = 0; i < 2048; i = i + 1 {
    selected.push("n\{i}")
  }
  let subset = try! flat.induced_subgraph(selected)
  assert_eq(subset.statistics().nodes, 2048)
  assert_eq(subset.statistics().edges, 8188)
  let sub_csr = try! subset
    .flat_graph(@moongraphml.GraphAddress::root(0))
    .to_csr()
  assert_eq(sub_csr.arc_count(), 8188)
  assert_eq(try! sub_csr.row(2047).length(), 0)
}
