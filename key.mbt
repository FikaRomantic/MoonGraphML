///|
pub(all) enum Scope {
  All
  DocumentScope
  GraphScope
  NodeScope
  EdgeScope
  PortScope
  HyperedgeScope
  EndpointScope
} derive(Eq, @debug.Debug)

///|
pub extend Scope with Eq::{equal, not_equal}

///|
pub extend Scope with @debug.Debug::{to_repr}

///|
pub fn Scope::from_name(name : String) -> Scope raise GraphError {
  match name {
    "all" => All
    "graphml" => DocumentScope
    "graph" => GraphScope
    "node" => NodeScope
    "edge" => EdgeScope
    "port" => PortScope
    "hyperedge" => HyperedgeScope
    "endpoint" => EndpointScope
    _ => raise InvalidGraph(path="key.for", reason="unknown scope \{name}")
  }
}

///|
pub fn Scope::name(self : Scope) -> String {
  match self {
    All => "all"
    DocumentScope => "graphml"
    GraphScope => "graph"
    NodeScope => "node"
    EdgeScope => "edge"
    PortScope => "port"
    HyperedgeScope => "hyperedge"
    EndpointScope => "endpoint"
  }
}

///|
pub fn Scope::applies_to(self : Scope, domain : Scope) -> Bool {
  self == All || self == domain
}

///|
pub(all) struct Key {
  id : String
  scope : Scope
  name : String?
  value_type : ValueType?
  default_value : DataValue?
  description : String?
  extra : Array[XmlAttributeValue]
}

///|
pub fn Key::new(
  id : String,
  scope : Scope,
  value_type : ValueType,
  name? : String,
  default_value? : Scalar,
  description? : String,
) -> Key raise GraphError {
  valid_token(id, "key.id")
  if default_value is Some(value) {
    require(
      value.value_type() == value_type,
      "key.default",
      "type does not match key",
    )
  }
  {
    id,
    scope,
    name,
    value_type: Some(value_type),
    default_value: default_value.map(fn(value) { ScalarValue(value) }),
    description,
    extra: [],
  }
}

///|
fn valid_token(value : String, path : String) -> Unit raise GraphError {
  require(value.length() > 0, path, "empty NMTOKEN")
  // XML 1.0 Fifth Edition NameChar ranges; NMTOKEN may begin with a digit.
  for ch in value {
    let c = ch.to_int()
    let ascii_name = (c >= 65 && c <= 90) ||
      (c >= 97 && c <= 122) ||
      (c >= 48 && c <= 57) ||
      c == 95 ||
      c == 58 ||
      c == 45 ||
      c == 46
    let unicode_name = (c >= 0xC0 && c <= 0xD6) ||
      (c >= 0xD8 && c <= 0xF6) ||
      (c >= 0xF8 && c <= 0x2FF) ||
      (c >= 0x370 && c <= 0x37D) ||
      (c >= 0x37F && c <= 0x1FFF) ||
      (c >= 0x200C && c <= 0x200D) ||
      (c >= 0x2070 && c <= 0x218F) ||
      (c >= 0x2C00 && c <= 0x2FEF) ||
      (c >= 0x3001 && c <= 0xD7FF) ||
      (c >= 0xF900 && c <= 0xFDCF) ||
      (c >= 0xFDF0 && c <= 0xFFFD) ||
      (c >= 0x10000 && c <= 0xEFFFF) ||
      c == 0xB7 ||
      (c >= 0x300 && c <= 0x36F) ||
      (c >= 0x203F && c <= 0x2040)
    require(ascii_name || unicode_name, path, "invalid NMTOKEN character")
  }
}
