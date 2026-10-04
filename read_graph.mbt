///|
priv struct ParseBudget {
  limits : Limits
  mut graphs : Int
  mut nodes : Int
  mut edges : Int
  mut ports : Int
  mut endpoints : Int
}

///|
fn ParseBudget::new(limits : Limits) -> ParseBudget {
  { limits, graphs: 0, nodes: 0, edges: 0, ports: 0, endpoints: 0, }
}

///|
fn read_description(
  children : Array[XmlElementValue],
  owner : String,
) -> String? raise GraphError {
  let mut result : String? = None
  for index = 0; index < children.length(); index = index + 1 {
    let child = children[index]
    if child.namespace_uri == Some(GRAPHML_URI) && child.name == "desc" {
      require(
        index == 0 && result is None,
        owner,
        "description must be first and unique",
      )
      result = Some(element_text(child))
    }
  }
  result
}

///|
fn read_node(
  element : XmlElementValue,
  keys : Map[String, Key],
  budget : ParseBudget,
) -> Node raise GraphError {
  graphml_element(element, "node")
  check_bound("nodes", budget.nodes + 1, budget.limits.nodes)
  budget.nodes = budget.nodes + 1
  let children = element_children(element)
  let node = Node::new(required_attribute(element, "id"))
  let description = read_description(children, "node")
  let locator = find_locator(children, "node")
  if locator is Some(_) {
    return {
      ..node,
      description,
      locator,
      extra: extra_attributes(element, ["id"]),
    }
  }
  let mut nested_graph : Graph? = None
  for child in children {
    require(
      child.namespace_uri == Some(GRAPHML_URI),
      "node",
      "unknown child namespace",
    )
    require(nested_graph is None, "node.graph", "nested graph must be last")
    match child.name {
      "desc" => ()
      "data" => node.data.push(read_datum(child, keys))
      "port" => node.ports.push(read_port(child, keys, budget))
      "graph" => nested_graph = Some(read_graph(child, keys, budget))
      _ => raise Unsupported(path="node", feature=child.name)
    }
  }
  {
    ..node,
    description,
    graph: nested_graph,
    extra: extra_attributes(element, ["id"]),
  }
}

///|
fn read_edge(
  element : XmlElementValue,
  keys : Map[String, Key],
  budget : ParseBudget,
) -> Edge raise GraphError {
  graphml_element(element, "edge")
  check_bound("edges", budget.edges + 1, budget.limits.edges)
  budget.edges = budget.edges + 1
  let children = element_children(element)
  let directed = match attribute_value(element, "directed") {
    Some(value) => {
      guard Scalar::parse(Boolean, value) is BooleanValue(direction) else {
        abort("boolean parser contract")
      }
      Some(direction)
    }
    None => None
  }
  let edge : Edge = {
    id: attribute_value(element, "id"),
    source: required_attribute(element, "source"),
    target: required_attribute(element, "target"),
    source_port: attribute_value(element, "sourceport"),
    target_port: attribute_value(element, "targetport"),
    directed,
    description: read_description(children, "edge"),
    data: [],
    graph: None,
    extra: extra_attributes(element, [
      "id", "source", "target", "sourceport", "targetport", "directed",
    ]),
  }
  let mut nested_graph : Graph? = None
  for child in children {
    require(
      child.namespace_uri == Some(GRAPHML_URI),
      "edge",
      "unknown child namespace",
    )
    require(nested_graph is None, "edge.graph", "nested graph must be last")
    match child.name {
      "desc" => ()
      "data" => edge.data.push(read_datum(child, keys))
      "graph" => nested_graph = Some(read_graph(child, keys, budget))
      _ => raise Unsupported(path="edge", feature=child.name)
    }
  }
  { ..edge, graph: nested_graph, }
}

///|
fn read_graph(
  element : XmlElementValue,
  keys : Map[String, Key],
  budget : ParseBudget,
) -> Graph raise GraphError {
  graphml_element(element, "graph")
  check_bound("graphs", budget.graphs + 1, budget.limits.graphs)
  budget.graphs = budget.graphs + 1
  let children = element_children(element)
  let graph : Graph = {
    id: attribute_value(element, "id"),
    edge_default: Direction::from_name(
      required_attribute(element, "edgedefault"),
    ),
    description: read_description(children, "graph"),
    data: [],
    nodes: [],
    edges: [],
    hyperedges: [],
    locator: None,
    extra: extra_attributes(element, ["id", "edgedefault"]),
  }
  let locator = find_locator(children, "graph")
  if locator is Some(_) {
    return { ..graph, locator, }
  }
  for child in children {
    require(
      child.namespace_uri == Some(GRAPHML_URI),
      "graph",
      "unknown child namespace",
    )
    match child.name {
      "desc" => ()
      "data" => graph.data.push(read_datum(child, keys))
      "node" => graph.nodes.push(read_node(child, keys, budget))
      "edge" => graph.edges.push(read_edge(child, keys, budget))
      "hyperedge" => graph.hyperedges.push(read_hyperedge(child, keys, budget))
      _ => raise Unsupported(path="graph", feature=child.name)
    }
  }
  graph
}

///|
pub fn parse(
  input : String,
  limits? : Limits = Limits::default(),
  profile? : ReadProfile = Strict,
) -> Document raise GraphError {
  let root = read_tree(input, limits)
  if profile == ReferenceLibraries {
    normalize_reference_tree(root)
  }
  let keys = read_keys(root, limits)
  let catalog = key_map(keys)
  let children = element_children(root)
  let doc : Document = {
    keys,
    graphs: [],
    data: [],
    description: read_description(children, "graphml"),
    extra: root.attributes.copy(),
  }
  let budget = ParseBudget::new(limits)
  for child in children {
    match child.name {
      "desc" | "key" => ()
      "graph" => doc.graphs.push(read_graph(child, catalog, budget))
      "data" => doc.data.push(read_datum(child, catalog))
      _ => raise Unsupported(path="graphml", feature=child.name)
    }
  }
  validate_hierarchy(doc, limits)
  doc
}

///|
fn check_data(
  data : Array[Datum],
  scope : Scope,
  catalog : Map[String, Key],
) -> Unit raise GraphError {
  let seen : Map[String, Bool] = Map([])
  for datum in data {
    valid_token(datum.key, "data.key")
    if datum.id is Some(id) {
      valid_token(id, "data.id")
    }
    require(
      !seen.contains(datum.key),
      scope.name(),
      "duplicate data key \{datum.key}",
    )
    seen[datum.key] = true
    let key = match catalog.get(datum.key) {
      Some(value) => value
      None =>
        raise InvalidGraph(
          path=scope.name(),
          reason="undefined key \{datum.key}",
        )
    }
    require(
      key.scope.applies_to(scope),
      scope.name(),
      "key scope does not apply",
    )
    validate_value(datum.value, key.value_type, "data.value")
  }
}

///|
fn unique_optional_id(
  id : String?,
  seen : Map[String, Bool],
  owner : String,
) -> Unit raise GraphError {
  if id is Some(value) {
    valid_token(value, owner)
    require(!seen.contains(value), owner, "duplicate identifier \{value}")
    seen[value] = true
  }
}
