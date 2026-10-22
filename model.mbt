///|
pub(all) enum Direction {
  Directed
  Undirected
} derive(Eq, @debug.Debug)

///|
pub extend Direction with Eq::{equal, not_equal}

///|
pub extend Direction with @debug.Debug::{to_repr}

///|
pub fn Direction::from_name(name : String) -> Direction raise GraphError {
  match name {
    "directed" => Directed
    "undirected" => Undirected
    _ =>
      raise InvalidGraph(
        path="graph.edgedefault",
        reason="invalid direction \{name}",
      )
  }
}

///|
pub fn Direction::name(self : Direction) -> String {
  match self {
    Directed => "directed"
    Undirected => "undirected"
  }
}

///|
pub(all) enum EndpointKind {
  In
  Out
  Undir
} derive(Eq, @debug.Debug)

///|
pub extend EndpointKind with Eq::{equal, not_equal}

///|
pub extend EndpointKind with @debug.Debug::{to_repr}

///|
pub fn EndpointKind::from_name(name : String) -> EndpointKind raise GraphError {
  match name {
    "in" => In
    "out" => Out
    "undir" => Undir
    _ =>
      raise InvalidGraph(
        path="endpoint.type",
        reason="invalid endpoint kind \{name}",
      )
  }
}

///|
pub fn EndpointKind::name(self : EndpointKind) -> String {
  match self {
    In => "in"
    Out => "out"
    Undir => "undir"
  }
}

///|
pub(all) enum DataValue {
  ScalarValue(Scalar)
  XmlPayload(Array[XmlValue])
}

///|
pub(all) struct Datum {
  key : String
  id : String?
  value : DataValue
  extra : Array[XmlAttributeValue]
  namespaces : Array[NamespaceBinding]
}

///|
pub fn Datum::new(key : String, value : Scalar, id? : String) -> Datum {
  { key, value: ScalarValue(value), id, extra: [], namespaces: [], }
}

///|
pub(all) struct Locator {
  href : String
  link_type : String?
  extra : Array[XmlAttributeValue]
  namespaces : Array[NamespaceBinding]
}

///|
pub(all) struct Graph {
  id : String?
  edge_default : Direction
  description : String?
  data : Array[Datum]
  nodes : Array[Node]
  edges : Array[Edge]
  hyperedges : Array[Hyperedge]
  locator : Locator?
  extra : Array[XmlAttributeValue]
  namespaces : Array[NamespaceBinding]
}

///|
pub fn Graph::new(
  edge_default : Direction,
  id? : String,
  description? : String,
) -> Graph {
  {
    id,
    edge_default,
    description,
    data: [],
    nodes: [],
    edges: [],
    hyperedges: [],
    locator: None,
    extra: [],
    namespaces: [],
  }
}

///|
pub(all) struct Node {
  id : String
  description : String?
  data : Array[Datum]
  ports : Array[Port]
  graph : Graph?
  locator : Locator?
  extra : Array[XmlAttributeValue]
  namespaces : Array[NamespaceBinding]
}

///|
pub fn Node::new(id : String, description? : String) -> Node {
  {
    id,
    description,
    data: [],
    ports: [],
    graph: None,
    locator: None,
    extra: [],
    namespaces: [],
  }
}

///|
pub(all) struct Edge {
  id : String?
  source : String
  target : String
  source_port : String?
  target_port : String?
  directed : Bool?
  description : String?
  data : Array[Datum]
  graph : Graph?
  extra : Array[XmlAttributeValue]
  namespaces : Array[NamespaceBinding]
}

///|
pub fn Edge::new(
  source : String,
  target : String,
  id? : String,
  directed? : Bool,
  source_port? : String,
  target_port? : String,
) -> Edge {
  {
    id,
    source,
    target,
    source_port,
    target_port,
    directed,
    description: None,
    data: [],
    graph: None,
    extra: [],
    namespaces: [],
  }
}

///|
pub fn Edge::effective_direction(self : Edge, graph : Graph) -> Direction {
  match self.directed {
    Some(true) => Directed
    Some(false) => Undirected
    None => graph.edge_default
  }
}

///|
pub(all) struct Port {
  name : String
  description : String?
  data : Array[Datum]
  ports : Array[Port]
  extra : Array[XmlAttributeValue]
  namespaces : Array[NamespaceBinding]
}

///|
pub fn Port::new(name : String, description? : String) -> Port {
  { name, description, data: [], ports: [], extra: [], namespaces: [], }
}

///|
pub(all) struct Hyperedge {
  id : String?
  description : String?
  data : Array[Datum]
  endpoints : Array[Endpoint]
  graph : Graph?
  extra : Array[XmlAttributeValue]
  namespaces : Array[NamespaceBinding]
}

///|
pub fn Hyperedge::new(id? : String, description? : String) -> Hyperedge {
  {
    id,
    description,
    data: [],
    endpoints: [],
    graph: None,
    extra: [],
    namespaces: [],
  }
}

///|
pub(all) struct Endpoint {
  id : String?
  node : String
  port : String?
  kind : EndpointKind
  description : String?
  extra : Array[XmlAttributeValue]
  namespaces : Array[NamespaceBinding]
}

///|
pub fn Endpoint::new(
  node : String,
  kind~ : EndpointKind = Undir,
  port? : String,
  id? : String,
) -> Endpoint {
  { id, node, port, kind, description: None, extra: [], namespaces: [], }
}

///|
pub struct Document {
  keys : Array[Key]
  graphs : Array[Graph]
  data : Array[Datum]
  description : String?
  extra : Array[XmlAttributeValue]
  namespaces : Array[NamespaceBinding]
}

///|
pub fn Document::graph_count(self : Document) -> Int32 {
  self.graphs.length()
}

///|
pub fn Document::key_count(self : Document) -> Int32 {
  self.keys.length()
}
