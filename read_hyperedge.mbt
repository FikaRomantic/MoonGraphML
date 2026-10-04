///|
fn read_endpoint(
  element : XmlElementValue,
  budget : ParseBudget,
) -> Endpoint raise GraphError {
  graphml_element(element, "endpoint")
  check_bound("endpoints", budget.endpoints + 1, budget.limits.endpoints)
  budget.endpoints = budget.endpoints + 1
  let children = element_children(element)
  for child in children {
    graphml_element(child, "desc")
  }
  {
    id: attribute_value(element, "id"),
    node: required_attribute(element, "node"),
    port: attribute_value(element, "port"),
    kind: EndpointKind::from_name(
      attribute_value(element, "type").unwrap_or("undir"),
    ),
    description: read_description(children, "endpoint"),
    extra: extra_attributes(element, ["id", "node", "port", "type"]),
    namespaces: element.namespaces,
  }
}

///|
fn read_hyperedge(
  element : XmlElementValue,
  keys : Map[String, Key],
  budget : ParseBudget,
) -> Hyperedge raise GraphError {
  graphml_element(element, "hyperedge")
  check_bound("edges_and_hyperedges", budget.edges + 1, budget.limits.edges)
  budget.edges = budget.edges + 1
  let children = element_children(element)
  let hyperedge : Hyperedge = {
    id: attribute_value(element, "id"),
    description: read_description(children, "hyperedge"),
    data: [],
    endpoints: [],
    graph: None,
    extra: extra_attributes(element, ["id"]),
    namespaces: element.namespaces,
  }
  let mut nested_graph : Graph? = None
  for child in children {
    require(
      child.namespace_uri == Some(GRAPHML_URI),
      "hyperedge",
      "unknown child namespace",
    )
    require(
      nested_graph is None,
      "hyperedge.graph",
      "nested graph must be last",
    )
    match child.name {
      "desc" => ()
      "data" => hyperedge.data.push(read_datum(child, keys))
      "endpoint" => hyperedge.endpoints.push(read_endpoint(child, budget))
      "graph" => nested_graph = Some(read_graph(child, keys, budget))
      _ => raise Unsupported(path="hyperedge", feature=child.name)
    }
  }
  { ..hyperedge, graph: nested_graph, }
}
