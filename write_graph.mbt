///|
fn write_locator(output : Output, locator : Locator) -> Unit raise GraphError {
  let attributes = [
    { namespace_uri: Some(XLINK_URI), name: "href", value: locator.href, },
  ]
  if locator.link_type is Some(value) {
    attributes.push({ namespace_uri: Some(XLINK_URI), name: "type", value, })
  }
  attributes.append(locator.extra)
  output.start("locator", attributes)
  output.end("locator")
}

///|
fn write_port(output : Output, port : Port) -> Unit raise GraphError {
  let attributes = [plain_attribute("name", port.name)]
  attributes.append(port.extra)
  output.start("port", attributes)
  write_description(output, port.description)
  write_data(output, port.data)
  for nested in port.ports {
    write_port(output, nested)
  }
  output.end("port")
}

///|
fn write_node(output : Output, node : Node) -> Unit raise GraphError {
  let attributes = [plain_attribute("id", node.id)]
  attributes.append(node.extra)
  output.start("node", attributes)
  write_description(output, node.description)
  match node.locator {
    Some(locator) => write_locator(output, locator)
    None => {
      write_data(output, node.data)
      for port in node.ports {
        write_port(output, port)
      }
      if node.graph is Some(graph) {
        write_graph(output, graph)
      }
    }
  }
  output.end("node")
}

///|
fn write_edge(output : Output, edge : Edge) -> Unit raise GraphError {
  let attributes = [
    plain_attribute("source", edge.source),
    plain_attribute("target", edge.target),
  ]
  optional_attribute(attributes, "id", edge.id)
  optional_attribute(attributes, "sourceport", edge.source_port)
  optional_attribute(attributes, "targetport", edge.target_port)
  if edge.directed is Some(value) {
    attributes.push(
      plain_attribute("directed", if value { "true" } else { "false" }),
    )
  }
  attributes.append(edge.extra)
  output.start("edge", attributes)
  write_description(output, edge.description)
  write_data(output, edge.data)
  if edge.graph is Some(graph) {
    write_graph(output, graph)
  }
  output.end("edge")
}

///|
fn write_endpoint(
  output : Output,
  endpoint : Endpoint,
) -> Unit raise GraphError {
  let attributes = [
    plain_attribute("node", endpoint.node),
    plain_attribute("type", endpoint.kind.name()),
  ]
  optional_attribute(attributes, "id", endpoint.id)
  optional_attribute(attributes, "port", endpoint.port)
  attributes.append(endpoint.extra)
  output.start("endpoint", attributes)
  write_description(output, endpoint.description)
  output.end("endpoint")
}

///|
fn write_hyperedge(
  output : Output,
  hyperedge : Hyperedge,
) -> Unit raise GraphError {
  let attributes = []
  optional_attribute(attributes, "id", hyperedge.id)
  attributes.append(hyperedge.extra)
  output.start("hyperedge", attributes)
  write_description(output, hyperedge.description)
  write_data(output, hyperedge.data)
  for endpoint in hyperedge.endpoints {
    write_endpoint(output, endpoint)
  }
  if hyperedge.graph is Some(graph) {
    write_graph(output, graph)
  }
  output.end("hyperedge")
}

///|
fn write_graph(output : Output, graph : Graph) -> Unit raise GraphError {
  let attributes = [plain_attribute("edgedefault", graph.edge_default.name())]
  optional_attribute(attributes, "id", graph.id)
  attributes.append(graph.extra)
  output.start("graph", attributes)
  write_description(output, graph.description)
  match graph.locator {
    Some(locator) => write_locator(output, locator)
    None => {
      write_data(output, graph.data)
      for node in graph.nodes {
        write_node(output, node)
      }
      for edge in graph.edges {
        write_edge(output, edge)
      }
      for hyperedge in graph.hyperedges {
        write_hyperedge(output, hyperedge)
      }
    }
  }
  output.end("graph")
}

///|
/// Serialize the supported GraphML information model, not its original XML spelling.
pub fn serialize(
  doc : Document,
  limits? : Limits = Limits::default(),
) -> String raise GraphError {
  limits.validate()
  let output = Output::new(limits)
  output.raw("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
  output.start("graphml", doc.extra, default_ns=GRAPHML_URI)
  write_description(output, doc.description)
  for key in doc.keys {
    write_key(output, key)
  }
  write_data(output, doc.data)
  for graph in doc.graphs {
    write_graph(output, graph)
  }
  output.end("graphml")
  output.finish()
}
