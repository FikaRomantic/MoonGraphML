///|
pub(all) suberror GraphError {
  InvalidXml(String)
  InvalidGraph(path~ : String, reason~ : String)
  LimitExceeded(resource~ : String, limit~ : Int32)
  Unsupported(path~ : String, feature~ : String)
} derive(Eq, @debug.Debug)

///|
pub extend GraphError with Eq::{equal, not_equal}

///|
pub extend GraphError with @debug.Debug::{to_repr}

///|
pub(all) struct Limits {
  input_bytes : Int32
  xml_depth : Int32
  xml_elements : Int32
  attributes_per_element : Int32
  text_bytes : Int32
  keys : Int32
  graphs : Int32
  nodes : Int32
  edges : Int32
  ports : Int32
  endpoints : Int32
  output_bytes : Int32
} derive(Eq, @debug.Debug)

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Limits with @debug.Debug::{to_repr}

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
  amount : Int32,
  bound : Int32,
) -> Unit raise GraphError {
  if amount < 0 || amount > bound {
    raise LimitExceeded(resource~, limit=bound)
  }
}

///|
fn utf8_size(text : String) -> Int32 raise GraphError {
  let mut bytes = 0
  let mut i = 0
  while i < text.length() {
    let unit = text.code_unit_at(i).to_int()
    let amount = if unit < 0x80 {
      1
    } else if unit < 0x800 {
      2
    } else if unit >= 0xD800 && unit <= 0xDBFF {
      require(i + 1 < text.length(), "xml.unicode", "unpaired high surrogate")
      let low = text.code_unit_at(i + 1).to_int()
      require(
        low >= 0xDC00 && low <= 0xDFFF,
        "xml.unicode",
        "unpaired high surrogate",
      )
      i = i + 1
      4
    } else {
      require(
        unit < 0xDC00 || unit > 0xDFFF,
        "xml.unicode",
        "unpaired low surrogate",
      )
      3
    }
    if bytes > 2147483647 - amount {
      raise LimitExceeded(resource="utf8_bytes", limit=2147483647)
    }
    bytes = bytes + amount
    i = i + 1
  }
  bytes
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
