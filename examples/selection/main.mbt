///|
fn main raise {
  let builder = @g.FlatBuilder::new([], Directed)
  for name in ["a", "b", "c"] {
    builder.add_node(name)
  }
  builder.add_edge("a", "b")
  builder.add_edge("a", "b")
  builder.add_edge("b", "c")
  let doc = builder.finish()
  let renamed = doc.relabel_nodes(0, [("a", "b"), ("b", "a")])
  let sample = renamed.flat_graph(@g.GraphAddress::root(0)).edge_subgraph([1])
  assert_eq(sample.graphs()[0].edges.length(), 1)
  assert_eq(sample.graphs()[0].nodes.length(), 2)
  assert_true(@g.parse(@g.serialize(sample)).equivalent(sample))
  println(
    "Atomic ID swaps preserve references; edge sampling keeps parallel edges individually and round-trips GraphML",
  )
}
