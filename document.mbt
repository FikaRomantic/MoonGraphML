///|
/// Construct an owned document. Validation is performed before detaching caller arrays.
pub fn Document::new(
  keys : Array[Key],
  graphs : Array[Graph],
  data? : Array[Datum] = [],
  description? : String,
  extra? : Array[XmlAttributeValue] = [],
  limits? : Limits = Limits::default(),
) -> Document raise GraphError {
  let candidate : Document = { keys, graphs, data, description, extra, }
  // The bounded exporter/parser pair also validates cycles, extra attributes and XML characters.
  // This is a one-time ownership boundary, not the fast path used by parse().
  validate_model(candidate, limits)
  parse(serialize(candidate, limits~), limits~)
}

///|
/// Return detached graphs. Changes to the returned arrays never mutate the document.
pub fn Document::graphs(self : Document) -> Array[Graph] {
  self.graphs.map(clone_graph)
}

///|
pub fn Document::keys(self : Document) -> Array[Key] {
  self.keys.map(clone_key)
}

///|
pub fn Document::data(self : Document) -> Array[Datum] {
  clone_data(self.data)
}

///|
pub fn Document::description(self : Document) -> String? {
  self.description
}

///|
pub fn Document::extra_attributes(self : Document) -> Array[XmlAttributeValue] {
  self.extra.copy()
}

///|
fn clone_xml(values : Array[XmlValue]) -> Array[XmlValue] {
  values.map(fn(value) {
    match value {
      Text(text) => Text(text)
      Element(element) =>
        Element({
          ..element,
          attributes: element.attributes.copy(),
          content: clone_xml(element.content),
        })
    }
  })
}

///|
fn clone_value(value : DataValue) -> DataValue {
  match value {
    ScalarValue(_) => value
    XmlPayload(content) => XmlPayload(clone_xml(content))
  }
}

///|
fn clone_key(key : Key) -> Key {
  {
    ..key,
    extra: key.extra.copy(),
    default_value: key.default_value.map(clone_value),
  }
}

///|
fn clone_data(data : Array[Datum]) -> Array[Datum] {
  data.map(fn(datum) {
    { ..datum, value: clone_value(datum.value), extra: datum.extra.copy(), }
  })
}

///|
fn clone_locator(locator : Locator) -> Locator {
  { ..locator, extra: locator.extra.copy(), }
}

///|
fn clone_port(port : Port) -> Port {
  {
    ..port,
    data: clone_data(port.data),
    ports: port.ports.map(clone_port),
    extra: port.extra.copy(),
  }
}

///|
fn clone_node(node : Node) -> Node {
  {
    ..node,
    data: clone_data(node.data),
    ports: node.ports.map(clone_port),
    graph: node.graph.map(clone_graph),
    locator: node.locator.map(clone_locator),
    extra: node.extra.copy(),
  }
}

///|
fn clone_edge(edge : Edge) -> Edge {
  {
    ..edge,
    data: clone_data(edge.data),
    graph: edge.graph.map(clone_graph),
    extra: edge.extra.copy(),
  }
}

///|
fn clone_hyperedge(hyperedge : Hyperedge) -> Hyperedge {
  {
    ..hyperedge,
    data: clone_data(hyperedge.data),
    endpoints: hyperedge.endpoints.map(fn(endpoint) {
      { ..endpoint, extra: endpoint.extra.copy(), }
    }),
    graph: hyperedge.graph.map(clone_graph),
    extra: hyperedge.extra.copy(),
  }
}

///|
fn clone_graph(graph : Graph) -> Graph {
  {
    ..graph,
    data: clone_data(graph.data),
    nodes: graph.nodes.map(clone_node),
    edges: graph.edges.map(clone_edge),
    hyperedges: graph.hyperedges.map(clone_hyperedge),
    locator: graph.locator.map(clone_locator),
    extra: graph.extra.copy(),
  }
}
