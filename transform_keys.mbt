///|
fn map_port_data(port : Port, transform : (Datum) -> Datum) -> Port {
  {
    ..port,
    data: port.data.map(transform),
    ports: port.ports.map(fn(child) { map_port_data(child, transform) }),
  }
}

///|
fn map_graph_data(graph : Graph, transform : (Datum) -> Datum) -> Graph {
  {
    ..graph,
    data: graph.data.map(transform),
    nodes: graph.nodes.map(fn(node) {
      {
        ..node,
        data: node.data.map(transform),
        ports: node.ports.map(fn(port) { map_port_data(port, transform) }),
        graph: node.graph.map(fn(nested) { map_graph_data(nested, transform) }),
      }
    }),
    edges: graph.edges.map(fn(edge) {
      {
        ..edge,
        data: edge.data.map(transform),
        graph: edge.graph.map(fn(nested) { map_graph_data(nested, transform) }),
      }
    }),
    hyperedges: graph.hyperedges.map(fn(hyperedge) {
      {
        ..hyperedge,
        data: hyperedge.data.map(transform),
        graph: hyperedge.graph.map(fn(nested) {
          map_graph_data(nested, transform)
        }),
      }
    }),
  }
}

///|
/// Rename a declaration and every corresponding data reference atomically.
pub fn Document::rename_key(
  self : Document,
  old_id : String,
  new_id : String,
  limits? : Limits = Limits::default(),
) -> Document raise GraphError {
  valid_token(new_id, "key.id")
  let catalog = key_map(self.keys)
  require(catalog.contains(old_id), "key.id", "key to rename does not exist")
  require(
    old_id == new_id || !catalog.contains(new_id),
    "key.id",
    "new key identifier already exists",
  )
  let keys = self.keys.map(fn(key) {
    if key.id == old_id {
      { ..key, id: new_id, }
    } else {
      key
    }
  })
  let transform = fn(datum : Datum) {
    if datum.key == old_id {
      { ..datum, key: new_id, }
    } else {
      datum
    }
  }
  Document::new(
    keys,
    self.graphs.map(fn(graph) { map_graph_data(graph, transform) }),
    data=self.data.map(transform),
    description?=self.description,
    extra=self.extra,
    namespaces=self.namespaces,
    limits~,
  )
}

///|
/// Replace a declaration, retaining its ID. Existing data must still satisfy its type and scope.
pub fn Document::replace_key(
  self : Document,
  key : Key,
  limits? : Limits = Limits::default(),
) -> Document raise GraphError {
  require(
    key_map(self.keys).contains(key.id),
    "key.id",
    "key to replace does not exist",
  )
  Document::new(
    self.keys.map(fn(existing) {
      if existing.id == key.id {
        key
      } else {
        existing
      }
    }),
    self.graphs,
    data=self.data,
    description?=self.description,
    extra=self.extra,
    namespaces=self.namespaces,
    limits~,
  )
}

///|
/// Removing an in-use key is intentionally forbidden, rather than silently discarding attributes.
pub fn Document::remove_key(
  self : Document,
  id : String,
  limits? : Limits = Limits::default(),
) -> Document raise GraphError {
  require(
    key_map(self.keys).contains(id),
    "key.id",
    "key to remove does not exist",
  )
  Document::new(
    self.keys.filter(fn(key) { key.id != id }),
    self.graphs,
    data=self.data,
    description?=self.description,
    extra=self.extra,
    namespaces=self.namespaces,
    limits~,
  )
}
