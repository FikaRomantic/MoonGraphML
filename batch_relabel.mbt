///|
fn relabel_graph(graph : Graph, mapping : Map[String, String]) -> Graph {
  {
    ..graph,
    extra: graph.extra.filter(a => {
      a.namespace_uri is Some(_) || a.name != "parse.nodeids"
    }),
    nodes: graph.nodes.map(node => {
      ..node,
      id: mapping.get(node.id).unwrap_or(node.id),
      graph: node.graph.map(g => relabel_graph(g, mapping)),
    }),
    edges: graph.edges.map(edge => {
      ..edge,
      source: mapping.get(edge.source).unwrap_or(edge.source),
      target: mapping.get(edge.target).unwrap_or(edge.target),
      graph: edge.graph.map(g => relabel_graph(g, mapping)),
    }),
    hyperedges: graph.hyperedges.map(edge => {
      ..edge,
      endpoints: edge.endpoints.map(e => {
        ..e,
        node: mapping.get(e.node).unwrap_or(e.node),
      }),
      graph: edge.graph.map(g => relabel_graph(g, mapping)),
    }),
  }
}

///|
/// Simultaneous relabeling in a top-level node-ID scope, including cycles and
/// swaps. References use the original mapping once, never chained substitutions.
/// XML payload business references are intentionally not interpreted.
pub fn Document::relabel_nodes(
  self : Document,
  root : Int32,
  replacements : Array[(String, String)],
  limits~ : Limits = Limits::default(),
) -> Document raise GraphError {
  limits.validate()
  bounded_index(root, self.graphs.length(), "relabel.root")
  check_bound("nodes", replacements.length(), limits.nodes)
  let mapping : Map[String, String] = Map([])
  let index = GraphIndex::new(self)
  for (old, next) in replacements {
    valid_token(next, "relabel.node")
    require(
      !mapping.contains(old),
      "relabel.node",
      "duplicate source identifier",
    )
    require(
      index.node_address(root, old) is Some(_),
      "relabel.node",
      "unknown source identifier",
    )
    mapping[old] = next
  }
  // Full result validation detects collisions against both renamed and unchanged IDs.
  self.replace_graph(
    GraphAddress::root(root),
    relabel_graph(self.graphs[root], mapping),
    limits~,
  )
}
