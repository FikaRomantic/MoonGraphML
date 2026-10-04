///|
fn validate_value(
  value : DataValue,
  kind : ValueType?,
  path : String,
) -> Unit raise GraphError {
  match value {
    ScalarValue(scalar) =>
      require(
        scalar.value_type() == kind.unwrap_or(StringValue),
        path,
        "scalar type does not match key",
      )
    XmlPayload(_) =>
      require(kind is None, path, "typed key cannot contain XML payload")
  }
}

///|
fn validate_locator(locator : Locator) -> Unit raise GraphError {
  require(
    locator.link_type is None || locator.link_type == Some("simple"),
    "locator.type",
    "only simple XLink supported",
  )
}

///|
fn validate_model_ports(
  ports : Array[Port],
  depth : Int,
  budget : ParseBudget,
) -> Unit raise GraphError {
  check_bound("port_depth", depth, budget.limits.xml_depth)
  for port in ports {
    check_bound("ports", budget.ports + 1, budget.limits.ports)
    budget.ports = budget.ports + 1
    validate_model_ports(port.ports, depth + 1, budget)
  }
}

///|
fn validate_model_graph(
  graph : Graph,
  depth : Int,
  budget : ParseBudget,
) -> Unit raise GraphError {
  check_bound("graph_depth", depth, budget.limits.xml_depth)
  check_bound("graphs", budget.graphs + 1, budget.limits.graphs)
  budget.graphs = budget.graphs + 1
  if graph.locator is Some(locator) {
    validate_locator(locator)
    require(
      graph.nodes.is_empty() &&
      graph.edges.is_empty() &&
      graph.hyperedges.is_empty() &&
      graph.data.is_empty(),
      "graph.locator",
      "locator and inline content are exclusive",
    )
  }
  for node in graph.nodes {
    check_bound("nodes", budget.nodes + 1, budget.limits.nodes)
    budget.nodes = budget.nodes + 1
    if node.locator is Some(locator) {
      validate_locator(locator)
      require(
        node.data.is_empty() && node.ports.is_empty() && node.graph is None,
        "node.locator",
        "locator and inline content are exclusive",
      )
    }
    validate_model_ports(node.ports, depth + 1, budget)
    if node.graph is Some(nested) {
      validate_model_graph(nested, depth + 1, budget)
    }
  }
  for edge in graph.edges {
    check_bound("edges", budget.edges + 1, budget.limits.edges)
    budget.edges = budget.edges + 1
    if edge.graph is Some(nested) {
      validate_model_graph(nested, depth + 1, budget)
    }
  }
  for hyperedge in graph.hyperedges {
    check_bound("edges", budget.edges + 1, budget.limits.edges)
    budget.edges = budget.edges + 1
    for _endpoint in hyperedge.endpoints {
      check_bound("endpoints", budget.endpoints + 1, budget.limits.endpoints)
      budget.endpoints = budget.endpoints + 1
    }
    if hyperedge.graph is Some(nested) {
      validate_model_graph(nested, depth + 1, budget)
    }
  }
}

///|
fn validate_model(doc : Document, limits : Limits) -> Unit raise GraphError {
  limits.validate()
  check_bound("keys", doc.keys.length(), limits.keys)
  let ids : Map[String, Bool] = Map([])
  for key in doc.keys {
    if key.name is Some(name) {
      valid_token(name, "key.attr.name")
    }
    unique_optional_id(Some(key.id), ids, "key.id")
    if key.default_value is Some(value) {
      validate_value(value, key.value_type, "key.default")
    }
  }
  let budget = ParseBudget::new(limits)
  for graph in doc.graphs {
    validate_model_graph(graph, 1, budget)
  }
  validate_hierarchy(doc, limits)
}
