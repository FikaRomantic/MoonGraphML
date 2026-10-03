///|
pub(all) suberror GraphError {
  InvalidXml(String)
  InvalidGraph(path~ : String, reason~ : String)
  LimitExceeded(resource~ : String, limit~ : Int)
  Unsupported(path~ : String, feature~ : String)
} derive(Eq, @debug.Debug)

///|
pub(all) struct Limits {
  input_bytes : Int
  xml_depth : Int
  xml_elements : Int
  attributes_per_element : Int
  text_bytes : Int
  keys : Int
  graphs : Int
  nodes : Int
  edges : Int
  ports : Int
  endpoints : Int
  output_bytes : Int
} derive(Eq, @debug.Debug)

///|
pub fn Limits::default() -> Limits {
  {
    input_bytes: 32 * 1024 * 1024,
    xml_depth: 64,
    xml_elements: 1000000,
    attributes_per_element: 64,
    text_bytes: 4 * 1024 * 1024,
    keys: 4096,
    graphs: 4096,
    nodes: 200000,
    edges: 1000000,
    ports: 1000000,
    endpoints: 1000000,
    output_bytes: 64 * 1024 * 1024,
  }
}

///|
pub fn Limits::validate(self : Limits) -> Unit raise GraphError {
  let bounds = [
    ("input_bytes", self.input_bytes),
    ("xml_depth", self.xml_depth),
    ("xml_elements", self.xml_elements),
    ("attributes_per_element", self.attributes_per_element),
    ("text_bytes", self.text_bytes),
    ("keys", self.keys),
    ("graphs", self.graphs),
    ("nodes", self.nodes),
    ("edges", self.edges),
    ("ports", self.ports),
    ("endpoints", self.endpoints),
    ("output_bytes", self.output_bytes),
  ]
  for (resource, limit) in bounds {
    if limit < 0 {
      raise InvalidGraph(path="limits", reason="negative \{resource}")
    }
  }
  if self.xml_depth > 256 {
    raise InvalidGraph(path="limits", reason="xml_depth must not exceed 256")
  }
}

///|
fn check_bound(
  resource : String,
  amount : Int,
  bound : Int,
) -> Unit raise GraphError {
  if amount < 0 || amount > bound {
    raise LimitExceeded(resource~, limit=bound)
  }
}

///|
fn utf8_size(text : String) -> Int {
  @utf8.encode(text).length()
}

///|
fn invalid(path : String, reason : String) -> Unit raise GraphError {
  raise InvalidGraph(path~, reason~)
}

///|
fn require(
  condition : Bool,
  path : String,
  reason : String,
) -> Unit raise GraphError {
  if !condition {
    invalid(path, reason)
  }
}
