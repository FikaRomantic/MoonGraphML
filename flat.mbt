///|
/// A lossless view of a single non-hierarchical binary graph.
pub struct FlatGraph {
  keys : Array[Key]
  graph : Graph
}

///|
fn require_flat(graph : Graph) -> Unit raise GraphError {
  require(
    graph.locator is None,
    "flat.graph",
    "external graph locator is not materialized",
  )
  require(
    graph.hyperedges.is_empty(),
    "flat.graph",
    "hyperedges need an explicit application projection",
  )
  for node in graph.nodes {
    require(
      node.graph is None,
      "flat.node",
      "nested graph cannot be silently flattened",
    )
    require(
      node.locator is None,
      "flat.node",
      "external node locator is not materialized",
    )
    require(
      node.ports.is_empty(),
      "flat.node",
      "ports cannot be silently discarded",
    )
  }
  for edge in graph.edges {
    require(
      edge.graph is None,
      "flat.edge",
      "nested edge graph cannot be discarded",
    )
    require(
      edge.source_port is None && edge.target_port is None,
      "flat.edge",
      "port references cannot be discarded",
    )
  }
}

///|
/// Reject advanced structures rather than silently translating them into a different graph.
pub fn Document::flat_graph(
  self : Document,
  address : GraphAddress,
) -> FlatGraph raise GraphError {
  let graph = graph_at(self, address)
  require_flat(graph)
  { keys: self.keys, graph, }
}

///|
pub fn FlatGraph::graph(self : FlatGraph) -> Graph {
  clone_graph(self.graph)
}

///|
/// Produce a one-graph document. Document-level metadata is outside this selected-graph view.
pub fn FlatGraph::to_document(
  self : FlatGraph,
  limits? : Limits = Limits::default(),
) -> Document raise GraphError {
  Document::new(self.keys, [self.graph], limits~)
}

///|
pub(all) struct NodeRow {
  id : String
  attributes : Map[String, Scalar]
}

///|
pub(all) struct EdgeRow {
  id : String?
  source : String
  target : String
  direction : Direction
  attributes : Map[String, Scalar]
}

///|
pub(all) struct IndexedEdge {
  id : String?
  source : Int
  target : Int
  direction : Direction
}

///|
fn row_values(
  keys : Array[Key],
  data : Array[Datum],
  scope : Scope,
  use_defaults : Bool,
) -> Map[String, Scalar] raise GraphError {
  let values : Map[String, Scalar] = Map([])
  for datum in data {
    match datum.value {
      ScalarValue(value) => values[datum.key] = value
      XmlPayload(_) =>
        raise Unsupported(
          path="flat.row",
          feature="XML attribute payload cannot be a scalar table cell",
        )
    }
  }
  if use_defaults {
    for key in keys {
      if key.scope.applies_to(scope) && !values.contains(key.id) {
        match key.default_value {
          Some(ScalarValue(value)) => values[key.id] = value
          Some(XmlPayload(_)) =>
            raise Unsupported(
              path="flat.row",
              feature="XML default cannot be a scalar table cell",
            )
          None => ()
        }
      }
    }
  }
  values
}

///|
/// Tables are an explicit projection: descriptions and XML metadata remain available in graph().
pub fn FlatGraph::node_rows(
  self : FlatGraph,
  use_defaults? : Bool = true,
) -> Array[NodeRow] raise GraphError {
  let result = []
  for node in self.graph.nodes {
    result.push({
      id: node.id,
      attributes: row_values(self.keys, node.data, NodeScope, use_defaults),
    })
  }
  result
}

///|
pub fn FlatGraph::edge_rows(
  self : FlatGraph,
  use_defaults? : Bool = true,
) -> Array[EdgeRow] raise GraphError {
  let result = []
  for edge in self.graph.edges {
    result.push({
      id: edge.id,
      source: edge.source,
      target: edge.target,
      direction: edge.effective_direction(self.graph),
      attributes: row_values(self.keys, edge.data, EdgeScope, use_defaults),
    })
  }
  result
}

///|
/// Stable positional endpoints allow direct use by existing graph algorithm libraries.
pub fn FlatGraph::indexed_edges(self : FlatGraph) -> Array[IndexedEdge] {
  let positions : Map[String, Int] = Map([])
  for i = 0; i < self.graph.nodes.length(); i = i + 1 {
    positions[self.graph.nodes[i].id] = i
  }
  self.graph.edges.map(fn(edge) {
    {
      id: edge.id,
      source: positions.get(edge.source).unwrap(),
      target: positions.get(edge.target).unwrap(),
      direction: edge.effective_direction(self.graph),
    }
  })
}

///|
/// Build a flat graph from typed table rows with explicit declarations, not inferred coercions.
pub fn from_rows(
  keys : Array[Key],
  nodes : Array[NodeRow],
  edges : Array[EdgeRow],
  edge_default? : Direction = Directed,
  graph_id? : String,
  limits? : Limits = Limits::default(),
) -> Document raise GraphError {
  let graph = Graph::new(edge_default, id?=graph_id)
  // Iterate declarations rather than maps, so output attribute ordering is reproducible.
  let catalog = key_map(keys)
  for row in nodes {
    let node = Node::new(row.id)
    for (key, _) in row.attributes {
      require(
        catalog.contains(key),
        "rows.node",
        "undefined attribute key \{key}",
      )
    }
    for key in keys {
      if row.attributes.get(key.id) is Some(value) {
        node.data.push(Datum::new(key.id, value))
      }
    }
    graph.nodes.push(node)
  }
  for row in edges {
    let edge = Edge::new(
      row.source,
      row.target,
      id?=row.id,
      directed=row.direction == Directed,
    )
    for (key, _) in row.attributes {
      require(
        catalog.contains(key),
        "rows.edge",
        "undefined attribute key \{key}",
      )
    }
    for key in keys {
      if row.attributes.get(key.id) is Some(value) {
        edge.data.push(Datum::new(key.id, value))
      }
    }
    graph.edges.push(edge)
  }
  Document::new(keys, [graph], limits~)
}
