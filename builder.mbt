///|
/// Batch construction avoids repeatedly revalidating the entire graph for each addition.
/// Forward node references are permitted; finish() validates them before producing a document.
pub struct FlatBuilder {
  keys : Array[Key]
  catalog : Map[String, Key]
  graph : Graph
  node_ids : Map[String, Bool]
  edge_ids : Map[String, Bool]
  limits : Limits
}

///|
pub fn FlatBuilder::new(
  keys : Array[Key],
  direction : Direction,
  graph_id? : String,
  description? : String,
  limits~ : Limits = Limits::default(),
) -> FlatBuilder raise GraphError {
  limits.validate()
  check_bound("graphs", 1, limits.graphs)
  if graph_id is Some(id) {
    valid_token(id, "graph.id")
  }
  let owned_keys = Document::new(keys, [], limits~).keys()
  {
    keys: owned_keys,
    catalog: key_map(owned_keys),
    graph: Graph::new(direction, id?=graph_id, description?),
    node_ids: Map([]),
    edge_ids: Map([]),
    limits,
  }
}

///|
fn builder_data(
  catalog : Map[String, Key],
  scope : Scope,
  values : Array[(String, Scalar)],
) -> Array[Datum] raise GraphError {
  let result = values.map(fn(pair) { Datum::new(pair.0, pair.1) })
  check_data(result, scope, catalog)
  result
}

///|
/// On failure, no node or ID is inserted. Scalar-only inputs cannot create cyclic XML trees.
pub fn FlatBuilder::add_node(
  self : FlatBuilder,
  id : String,
  attributes~ : Array[(String, Scalar)] = [],
  description? : String,
) -> Unit raise GraphError {
  valid_token(id, "node.id")
  require(!self.node_ids.contains(id), "node.id", "duplicate node identifier")
  check_bound("nodes", self.graph.nodes.length() + 1, self.limits.nodes)
  let data = builder_data(self.catalog, NodeScope, attributes)
  let node = { ..Node::new(id, description?), data, }
  self.graph.nodes.push(node)
  self.node_ids[id] = true
}

///|
pub fn FlatBuilder::add_edge(
  self : FlatBuilder,
  source : String,
  target : String,
  id? : String,
  directed? : Bool,
  attributes~ : Array[(String, Scalar)] = [],
  description? : String,
) -> Unit raise GraphError {
  valid_token(source, "edge.source")
  valid_token(target, "edge.target")
  if id is Some(value) {
    valid_token(value, "edge.id")
    require(
      !self.edge_ids.contains(value),
      "edge.id",
      "duplicate edge identifier",
    )
  }
  check_bound("edges", self.graph.edges.length() + 1, self.limits.edges)
  let data = builder_data(self.catalog, EdgeScope, attributes)
  let edge = { ..Edge::new(source, target, id?, directed?), data, description, }
  self.graph.edges.push(edge)
  if id is Some(value) {
    self.edge_ids[value] = true
  }
}

///|
/// Set graph data as a complete replacement, with duplicate/scope/type checks before mutation.
pub fn FlatBuilder::set_graph_data(
  self : FlatBuilder,
  attributes : Array[(String, Scalar)],
) -> Unit raise GraphError {
  let data = builder_data(self.catalog, GraphScope, attributes)
  self.graph.data.clear()
  self.graph.data.append(data)
}

///|
pub fn FlatBuilder::node_count(self : FlatBuilder) -> Int32 {
  self.graph.nodes.length()
}

///|
pub fn FlatBuilder::edge_count(self : FlatBuilder) -> Int32 {
  self.graph.edges.length()
}

///|
/// Finish is repeatable; subsequent builder changes cannot mutate already returned documents.
pub fn FlatBuilder::finish(self : FlatBuilder) -> Document raise GraphError {
  Document::new(self.keys, [self.graph], limits=self.limits)
}
