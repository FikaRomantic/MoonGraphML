///|
fn child_graphs(graph : Graph) -> Array[Graph] {
  let result = []
  for node in graph.nodes {
    if node.graph is Some(nested) {
      result.push(nested)
    }
  }
  for edge in graph.edges {
    if edge.graph is Some(nested) {
      result.push(nested)
    }
  }
  for hyperedge in graph.hyperedges {
    if hyperedge.graph is Some(nested) {
      result.push(nested)
    }
  }
  result
}

///|
priv struct Region {
  nodes : Map[String, Node]
  edges : Map[String, Bool]
  hyperedges : Map[String, Bool]
  endpoints : Map[String, Bool]
}

///|
fn Region::new() -> Region {
  { nodes: Map([]), edges: Map([]), hyperedges: Map([]), endpoints: Map([]), }
}

///|
fn collect_region(
  graph : Graph,
  region : Region,
  depth : Int,
  limits : Limits,
) -> Unit raise GraphError {
  check_bound("graph_depth", depth, limits.xml_depth)
  for node in graph.nodes {
    valid_token(node.id, "node.id")
    require(
      !region.nodes.contains(node.id),
      "node.id",
      "duplicate descendant node \{node.id}",
    )
    region.nodes[node.id] = node
  }
  for edge in graph.edges {
    valid_token(edge.source, "edge.source")
    valid_token(edge.target, "edge.target")
    unique_optional_id(edge.id, region.edges, "edge.id")
  }
  for hyperedge in graph.hyperedges {
    unique_optional_id(hyperedge.id, region.hyperedges, "hyperedge.id")
    for endpoint in hyperedge.endpoints {
      valid_token(endpoint.node, "endpoint.node")
      unique_optional_id(endpoint.id, region.endpoints, "endpoint.id")
    }
  }
  for nested in child_graphs(graph) {
    collect_region(nested, region, depth + 1, limits)
  }
}

///|
fn validate_region(
  graph : Graph,
  catalog : Map[String, Key],
  graph_ids : Map[String, Bool],
  depth : Int,
  limits : Limits,
) -> Unit raise GraphError {
  check_bound("graph_depth", depth, limits.xml_depth)
  unique_optional_id(graph.id, graph_ids, "graph.id")
  let _ = graph.parse_info()
  check_data(graph.data, GraphScope, catalog)
  let region = Region::new()
  collect_region(graph, region, 0, limits)
  let node_ports : Map[String, Map[String, Bool]] = Map([])
  for (id, node) in region.nodes {
    let names : Map[String, Bool] = Map([])
    collect_ports(node.ports, names, catalog)
    node_ports[id] = names
  }
  for node in graph.nodes {
    let _ = node.degree_hints()
    let descendant_ports : Map[String, Bool] = Map([])
    collect_ports(node.ports, descendant_ports, catalog)
    if node.graph is Some(nested) {
      collect_descendant_ports(nested, descendant_ports, catalog)
    }
    check_data(node.data, NodeScope, catalog)
  }
  for edge in graph.edges {
    require(
      region.nodes.contains(edge.source),
      "edge.source",
      "node outside graph subtree: \{edge.source}",
    )
    require(
      region.nodes.contains(edge.target),
      "edge.target",
      "node outside graph subtree: \{edge.target}",
    )
    check_port_reference(edge.source_port, edge.source, node_ports)
    check_port_reference(edge.target_port, edge.target, node_ports)
    check_data(edge.data, EdgeScope, catalog)
  }
  for hyperedge in graph.hyperedges {
    check_data(hyperedge.data, HyperedgeScope, catalog)
    for endpoint in hyperedge.endpoints {
      require(
        region.nodes.contains(endpoint.node),
        "endpoint.node",
        "node outside graph subtree: \{endpoint.node}",
      )
      check_port_reference(endpoint.port, endpoint.node, node_ports)
    }
  }
  for nested in child_graphs(graph) {
    validate_region(nested, catalog, graph_ids, depth + 1, limits)
  }
}

///|
/// XSD port_name_key uses .//g:port relative to each node, including nested graphs.
fn collect_descendant_ports(
  graph : Graph,
  names : Map[String, Bool],
  catalog : Map[String, Key],
) -> Unit raise GraphError {
  for node in graph.nodes {
    collect_ports(node.ports, names, catalog)
  }
  for nested in child_graphs(graph) {
    collect_descendant_ports(nested, names, catalog)
  }
}

///|
fn validate_hierarchy(doc : Document, limits : Limits) -> Unit raise GraphError {
  let catalog = key_map(doc.keys)
  check_data(doc.data, DocumentScope, catalog)
  let graph_ids : Map[String, Bool] = Map([])
  for graph in doc.graphs {
    validate_region(graph, catalog, graph_ids, 0, limits)
  }
}
