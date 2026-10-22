///|
/// XML Schema nonNegativeInteger has no machine-word upper bound.
pub struct CountHint {
  priv decimal : String
}

///|
pub fn CountHint::parse(input : String) -> CountHint raise GraphError {
  let token = input.trim(chars=" \t\r\n").to_owned()
  let negative = token.has_prefix("-")
  let start = if token.has_prefix("+") || negative { 1 } else { 0 }
  require(token.length() > start, "parse.count", "empty nonnegative integer")
  for i = start; i < token.length(); i = i + 1 {
    let c = token.code_unit_at(i).to_int()
    require(c >= 48 && c <= 57, "parse.count", "invalid nonnegative integer")
  }
  let mut first = start
  while first + 1 < token.length() && token.code_unit_at(first).to_int() == 48 {
    first = first + 1
  }
  let decimal = token[first:].to_owned()
  require(!negative || decimal == "0", "parse.count", "negative integer")
  { decimal, }
}

///|
pub fn CountHint::decimal(self : CountHint) -> String {
  self.decimal
}

///|
/// Return None on machine-word overflow without invalidating a legal XML Schema value.
pub fn CountHint::to_int64(self : CountHint) -> Int64? {
  Some(@string.parse_int64(self.decimal)) catch {
    _ => None
  }
}

///|
pub(all) enum IdHint {
  CanonicalIds
  FreeIds
} derive(Eq, @debug.Debug)

///|
pub extend IdHint with Eq::{equal, not_equal}

///|
pub extend IdHint with @debug.Debug::{to_repr}

///|
pub(all) enum OrderHint {
  FreeOrder
  NodesFirst
  AdjacencyList
} derive(Eq, @debug.Debug)

///|
pub extend OrderHint with Eq::{equal, not_equal}

///|
pub extend OrderHint with @debug.Debug::{to_repr}

///|
pub(all) struct ParseInfo {
  nodes : CountHint?
  edges : CountHint?
  max_in_degree : CountHint?
  max_out_degree : CountHint?
  node_ids : IdHint?
  edge_ids : IdHint?
  order : OrderHint?
}

///|
pub(all) struct DegreeHints {
  in_degree : CountHint?
  out_degree : CountHint?
}

///|
fn hint_attribute(
  attributes : Array[XmlAttributeValue],
  name : String,
) -> String? {
  for attribute in attributes {
    if attribute.namespace_uri is None && attribute.name == name {
      return Some(attribute.value)
    }
  }
  None
}

///|
fn count_hint(
  attributes : Array[XmlAttributeValue],
  name : String,
) -> CountHint? raise GraphError {
  match hint_attribute(attributes, name) {
    Some(value) => Some(CountHint::parse(value))
    None => None
  }
}

///|
fn id_hint(
  attributes : Array[XmlAttributeValue],
  name : String,
) -> IdHint? raise GraphError {
  match
    hint_attribute(attributes, name).map(fn(value) {
      value.trim(chars=" \t\r\n").to_owned()
    }) {
    Some("canonical") => Some(CanonicalIds)
    Some("free") => Some(FreeIds)
    None => None
    _ => raise InvalidGraph(path=name, reason="expected canonical or free")
  }
}

///|
/// Parse hints are advisory metadata; lexical validity does not prove content consistency.
pub fn Graph::parse_info(self : Graph) -> ParseInfo raise GraphError {
  let order = match
    hint_attribute(self.extra, "parse.order").map(fn(value) {
      value.trim(chars=" \t\r\n").to_owned()
    }) {
    Some("free") => Some(FreeOrder)
    Some("nodesfirst") => Some(NodesFirst)
    Some("adjacencylist") => Some(AdjacencyList)
    None => None
    _ => raise InvalidGraph(path="parse.order", reason="invalid order hint")
  }
  {
    nodes: count_hint(self.extra, "parse.nodes"),
    edges: count_hint(self.extra, "parse.edges"),
    max_in_degree: count_hint(self.extra, "parse.maxindegree"),
    max_out_degree: count_hint(self.extra, "parse.maxoutdegree"),
    node_ids: id_hint(self.extra, "parse.nodeids"),
    edge_ids: id_hint(self.extra, "parse.edgeids"),
    order,
  }
}

///|
pub fn Node::degree_hints(self : Node) -> DegreeHints raise GraphError {
  {
    in_degree: count_hint(self.extra, "parse.indegree"),
    out_degree: count_hint(self.extra, "parse.outdegree"),
  }
}

///|
/// Explicit flat-profile check. Nested graphs are intentionally not assigned invented counting rules.
pub fn ParseInfo::check_flat_counts(
  self : ParseInfo,
  graph : Graph,
) -> Unit raise GraphError {
  require_flat(graph)
  if self.nodes is Some(count) {
    require(
      count.decimal == graph.nodes.length().to_string(),
      "parse.nodes",
      "flat node count disagrees with stored structure",
    )
  }
  if self.edges is Some(count) {
    require(
      count.decimal == graph.edges.length().to_string(),
      "parse.edges",
      "flat edge count disagrees with stored structure",
    )
  }
  if self.node_ids == Some(CanonicalIds) {
    for i = 0; i < graph.nodes.length(); i = i + 1 {
      require(
        graph.nodes[i].id == "n\{i}",
        "parse.nodeids",
        "flat canonical node IDs must follow n0,n1,...",
      )
    }
  }
  if self.edge_ids == Some(CanonicalIds) {
    for i = 0; i < graph.edges.length(); i = i + 1 {
      require(
        graph.edges[i].id == Some("e\{i}"),
        "parse.edgeids",
        "flat canonical edge IDs must follow e0,e1,...",
      )
    }
  }
}
