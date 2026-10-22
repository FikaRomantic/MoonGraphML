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
  limits~ : Limits = Limits::default(),
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
  source : Int32
  target : Int32
  direction : Direction
}

///|
fn row_values(
  data : Array[Datum],
  defaults : Array[Key],
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
  for key in defaults {
    if !values.contains(key.id) {
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
  values
}

///|
fn table_defaults(
  keys : Array[Key],
  scope : Scope,
  use_defaults : Bool,
) -> Array[Key] {
  if use_defaults {
    keys.filter(fn(key) {
      key.scope.applies_to(scope) && key.default_value is Some(_)
    })
  } else {
    []
  }
}

///|
/// Tables are an explicit projection: descriptions and XML metadata remain available in graph().
pub fn FlatGraph::node_rows(
  self : FlatGraph,
  use_defaults~ : Bool = true,
) -> Array[NodeRow] raise GraphError {
  let defaults = table_defaults(self.keys, NodeScope, use_defaults)
  let result = []
  for node in self.graph.nodes {
    result.push({ id: node.id, attributes: row_values(node.data, defaults), })
  }
  result
}

///|
pub fn FlatGraph::edge_rows(
  self : FlatGraph,
  use_defaults~ : Bool = true,
) -> Array[EdgeRow] raise GraphError {
  let defaults = table_defaults(self.keys, EdgeScope, use_defaults)
  let result = []
  for edge in self.graph.edges {
    result.push({
      id: edge.id,
      source: edge.source,
      target: edge.target,
      direction: edge.effective_direction(self.graph),
      attributes: row_values(edge.data, defaults),
    })
  }
  result
}

///|
fn ordered_row_data(
  values : Map[String, Scalar],
  ordinals : Map[String, Int32],
  path : String,
) -> Array[Datum] raise GraphError {
  let ranked : Array[(Int32, Datum)] = []
  for (id, value) in values {
    let ordinal = match ordinals.get(id) {
      Some(index) => index
      None => raise InvalidGraph(path~, reason="undefined attribute key \{id}")
    }
    ranked.push((ordinal, Datum::new(id, value)))
  }
  ranked.sort_by_key(fn(item) { item.0 })
  ranked.map(fn(item) { item.1 })
}

///|
/// Stable positional endpoints allow direct use by existing graph algorithm libraries.
pub fn FlatGraph::indexed_edges(self : FlatGraph) -> Array[IndexedEdge] {
  let positions : Map[String, Int32] = Map([])
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
  edge_default~ : Direction = Directed,
  graph_id? : String,
  limits~ : Limits = Limits::default(),
) -> Document raise GraphError {
  limits.validate()
  check_bound("keys", keys.length(), limits.keys)
  check_bound("graphs", 1, limits.graphs)
  check_bound("nodes", nodes.length(), limits.nodes)
  check_bound("edges", edges.length(), limits.edges)
  let graph = Graph::new(edge_default, id?=graph_id)
  // Rank declarations once, then order only authored attributes in each sparse row.
  let ordinals : Map[String, Int32] = Map([])
  for index = 0; index < keys.length(); index = index + 1 {
    ordinals[keys[index].id] = index
  }
  for row in nodes {
    let node = {
      ..Node::new(row.id),
      data: ordered_row_data(row.attributes, ordinals, "rows.node"),
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
    graph.edges.push({
      ..edge,
      data: ordered_row_data(row.attributes, ordinals, "rows.edge"),
    })
  }
  Document::new(keys, [graph], limits~)
}
