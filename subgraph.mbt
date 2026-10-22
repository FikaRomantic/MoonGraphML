///|
// Topology-derived hints cannot safely describe a filtered graph. Keep extension
// attributes, even when their local names resemble GraphML's unqualified hints.
fn subgraph_extra(
  attributes : Array[XmlAttributeValue],
) -> Array[XmlAttributeValue] {
  attributes.filter(fn(attribute) {
    attribute.namespace_uri is Some(_) || !attribute.name.has_prefix("parse.")
  })
}

///|
/// Copy a node-induced subgraph, retaining source order and all edges whose two
/// endpoints are selected. Unknown or repeated node IDs are errors, not typos
/// silently ignored. Keys, defaults and graph/element XML metadata are retained;
/// topology-derived parse hints are removed. Document-level metadata is outside
/// a FlatGraph view. The resulting Document is independently owned and validated.
pub fn FlatGraph::induced_subgraph(
  self : FlatGraph,
  node_ids : Array[String],
  limits~ : Limits = Limits::default(),
) -> Document raise GraphError {
  limits.validate()
  check_bound("nodes", node_ids.length(), limits.nodes)
  let selected : Map[String, Bool] = Map([])
  for id in node_ids {
    require(
      !selected.contains(id),
      "subgraph.nodes",
      "duplicate selection \{id}",
    )
    selected[id] = true
  }
  let nodes : Array[Node] = []
  for node in self.graph.nodes {
    if selected.contains(node.id) {
      nodes.push({ ..node, extra: subgraph_extra(node.extra), })
    }
  }
  require(
    nodes.length() == selected.length(),
    "subgraph.nodes",
    "selection contains an unknown node ID",
  )
  let edges : Array[Edge] = []
  for edge in self.graph.edges {
    if selected.contains(edge.source) && selected.contains(edge.target) {
      // Check before growing the retained edge array.
      check_bound("edges", edges.length() + 1, limits.edges)
      edges.push(edge)
    }
  }
  let graph = {
    ..self.graph,
    nodes,
    edges,
    extra: subgraph_extra(self.graph.extra),
  }
  Document::new(self.keys, [graph], limits~)
}
