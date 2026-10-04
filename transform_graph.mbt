///|
fn replace_nested_graph(
  graph : Graph,
  steps : Array[GraphStep],
  position : Int,
  replacement : Graph,
) -> Graph raise GraphError {
  if position == steps.length() {
    return replacement
  }
  match steps[position] {
    NodeGraph(index) => {
      bounded_index(index, graph.nodes.length(), "replace.node")
      let node = graph.nodes[index]
      let nested = node.graph.unwrap_or_else(() => {
        raise InvalidGraph(path="replace.node", reason="missing nested graph")
      })
      let updated = replace_nested_graph(
        nested,
        steps,
        position + 1,
        replacement,
      )
      let nodes = graph.nodes.copy()
      nodes[index] = { ..node, graph: Some(updated), }
      { ..graph, nodes, }
    }
    EdgeGraph(index) => {
      bounded_index(index, graph.edges.length(), "replace.edge")
      let edge = graph.edges[index]
      let nested = edge.graph.unwrap_or_else(() => {
        raise InvalidGraph(path="replace.edge", reason="missing nested graph")
      })
      let updated = replace_nested_graph(
        nested,
        steps,
        position + 1,
        replacement,
      )
      let edges = graph.edges.copy()
      edges[index] = { ..edge, graph: Some(updated), }
      { ..graph, edges, }
    }
    HyperedgeGraph(index) => {
      bounded_index(index, graph.hyperedges.length(), "replace.hyperedge")
      let hyperedge = graph.hyperedges[index]
      let nested = hyperedge.graph.unwrap_or_else(() => {
        raise InvalidGraph(
          path="replace.hyperedge",
          reason="missing nested graph",
        )
      })
      let updated = replace_nested_graph(
        nested,
        steps,
        position + 1,
        replacement,
      )
      let hyperedges = graph.hyperedges.copy()
      hyperedges[index] = { ..hyperedge, graph: Some(updated), }
      { ..graph, hyperedges, }
    }
  }
}

///|
/// Replace a graph atomically. Ancestor references and global IDs are revalidated.
pub fn Document::replace_graph(
  self : Document,
  address : GraphAddress,
  replacement : Graph,
  limits? : Limits = Limits::default(),
) -> Document raise GraphError {
  bounded_index(address.root, self.graphs.length(), "replace.root")
  check_bound("graph_address_depth", address.steps.length(), limits.xml_depth)
  let graphs = self.graphs.copy()
  graphs[address.root] = replace_nested_graph(
    graphs[address.root],
    address.steps,
    0,
    replacement,
  )
  Document::new(
    self.keys,
    graphs,
    data=self.data,
    description?=self.description,
    extra=self.extra,
    namespaces=self.namespaces,
    limits~,
  )
}

///|
/// Add a top-level graph without merging ID scopes or changing existing addresses.
pub fn Document::append_graph(
  self : Document,
  graph : Graph,
  limits? : Limits = Limits::default(),
) -> Document raise GraphError {
  let graphs = self.graphs.copy()
  graphs.push(graph)
  Document::new(
    self.keys,
    graphs,
    data=self.data,
    description?=self.description,
    extra=self.extra,
    namespaces=self.namespaces,
    limits~,
  )
}

///|
/// Keep selected top-level graphs, retaining the shared key catalog and document attributes.
pub fn Document::select_graphs(
  self : Document,
  roots : Array[Int],
  limits? : Limits = Limits::default(),
) -> Document raise GraphError {
  let graphs = []
  let seen : Map[Int, Bool] = Map([])
  for root in roots {
    bounded_index(root, self.graphs.length(), "select.root")
    require(!seen.contains(root), "select.root", "duplicate root selection")
    seen[root] = true
    graphs.push(self.graphs[root])
  }
  Document::new(
    self.keys,
    graphs,
    data=self.data,
    description?=self.description,
    extra=self.extra,
    namespaces=self.namespaces,
    limits~,
  )
}
