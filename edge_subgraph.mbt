///|
/// Edge-index selection retains parallel and anonymous edges independently.
/// Source order, typed defaults and XML metadata survive; stale topology hints
/// are removed. No document-root metadata exists in a FlatGraph view.
pub fn FlatGraph::edge_subgraph(
  self : FlatGraph,
  edge_indices : Array[Int32],
  keep_isolated~ : Bool = false,
  limits~ : Limits = Limits::default(),
) -> Document raise GraphError {
  limits.validate()
  check_bound("edges", edge_indices.length(), limits.edges)
  let selected : Map[Int32, Bool] = Map([])
  let endpoints : Map[String, Bool] = Map([])
  for i in edge_indices {
    bounded_index(i, self.graph.edges.length(), "edge_selection.index")
    require(
      !selected.contains(i),
      "edge_selection.index",
      "duplicate edge index",
    )
    selected[i] = true
    let edge = self.graph.edges[i]
    endpoints[edge.source] = true
    endpoints[edge.target] = true
  }
  let nodes : Array[Node] = []
  for node in self.graph.nodes {
    if keep_isolated || endpoints.contains(node.id) {
      check_bound("nodes", nodes.length() + 1, limits.nodes)
      nodes.push({ ..node, extra: subgraph_extra(node.extra), })
    }
  }
  let edges : Array[Edge] = []
  for i, edge in self.graph.edges {
    if selected.contains(i) {
      edges.push(edge)
    }
  }
  Document::new(
    self.keys,
    [{ ..self.graph, nodes, edges, extra: subgraph_extra(self.graph.extra), }],
    limits~,
  )
}
