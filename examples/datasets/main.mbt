///|
fn main raise {
  let input = "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><key id=\"weight\" for=\"edge\" attr.type=\"double\"><default>1.5</default></key><graph edgedefault=\"undirected\"><node id=\"sample1\"/><node id=\"sample2\"/><edge source=\"sample1\" target=\"sample2\"/><edge source=\"sample1\" target=\"sample2\"><data key=\"weight\">2.5</data></edge></graph></graphml>"
  let document = try! @graphml.parse(input)
  let flat = try! document.flat_graph(@graphml.GraphAddress::root(0))
  let rows = try! flat.edge_rows()
  assert_eq(rows.length(), 2)
  assert_true(
    rows[0].attributes.get("weight") is Some(@graphml.DoubleValue(1.5)),
  )
  let indexed = flat.indexed_edges()
  assert_eq(indexed[0].source, 0)
  assert_eq(indexed[0].target, 1)
  let merged = try! document.merge(document, "dataset2_")
  assert_eq(merged.document.statistics().nodes, 4)
  println(
    "typed rows=\{rows.length()} merged graphs=\{merged.document.graph_count()}",
  )
}
