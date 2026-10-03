///|
fn attributes_equal(
  left : Array[XmlAttributeValue],
  right : Array[XmlAttributeValue],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let lookup : Map[(String?, String), String] = Map([])
  for attribute in left {
    lookup[(attribute.namespace_uri, attribute.name)] = attribute.value
  }
  right.all(fn(attribute) {
    lookup.get((attribute.namespace_uri, attribute.name)) ==
    Some(attribute.value)
  })
}

///|
fn normalized_content(content : Array[XmlValue]) -> Array[XmlValue] {
  let result : Array[XmlValue] = []
  let mut text = StringBuilder()
  for value in content {
    match value {
      Text(value) => text.write_string(value)
      Element(_) => {
        let pending = text.to_string()
        if pending != "" {
          result.push(Text(pending))
        }
        text = StringBuilder()
        result.push(value)
      }
    }
  }
  let pending = text.to_string()
  if pending != "" {
    result.push(Text(pending))
  }
  result
}

///|
fn xml_equal(left : Array[XmlValue], right : Array[XmlValue]) -> Bool {
  let left = normalized_content(left)
  let right = normalized_content(right)
  if left.length() != right.length() {
    return false
  }
  for i = 0; i < left.length(); i = i + 1 {
    let same = match (left[i], right[i]) {
      (Text(a), Text(b)) => a == b
      (Element(a), Element(b)) =>
        a.namespace_uri == b.namespace_uri &&
        a.name == b.name &&
        attributes_equal(a.attributes, b.attributes) &&
        xml_equal(a.content, b.content)
      _ => false
    }
    if !same {
      return false
    }
  }
  true
}

///|
fn values_equal(left : DataValue, right : DataValue) -> Bool {
  match (left, right) {
    (ScalarValue(a), ScalarValue(b)) => a.equivalent(b)
    (XmlPayload(a), XmlPayload(b)) => xml_equal(a, b)
    _ => false
  }
}

///|
fn optional_values_equal(left : DataValue?, right : DataValue?) -> Bool {
  match (left, right) {
    (None, None) => true
    (Some(a), Some(b)) => values_equal(a, b)
    _ => false
  }
}

///|
fn data_equal(left : Array[Datum], right : Array[Datum]) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let lookup : Map[String, Datum] = Map([])
  for datum in left {
    lookup[datum.key] = datum
  }
  right.all(fn(datum) {
    match lookup.get(datum.key) {
      Some(other) =>
        other.id == datum.id &&
        values_equal(other.value, datum.value) &&
        attributes_equal(other.extra, datum.extra)
      None => false
    }
  })
}

///|
fn locators_equal(left : Locator?, right : Locator?) -> Bool {
  match (left, right) {
    (None, None) => true
    (Some(a), Some(b)) =>
      a.href == b.href &&
      a.link_type.unwrap_or("simple") == b.link_type.unwrap_or("simple") &&
      attributes_equal(a.extra, b.extra)
    _ => false
  }
}

///|
fn ports_equal(left : Array[Port], right : Array[Port]) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for i = 0; i < left.length(); i = i + 1 {
    let a = left[i]
    let b = right[i]
    if a.name != b.name ||
      a.description != b.description ||
      !data_equal(a.data, b.data) ||
      !attributes_equal(a.extra, b.extra) ||
      !ports_equal(a.ports, b.ports) {
      return false
    }
  }
  true
}

///|
fn optional_graphs_equal(left : Graph?, right : Graph?) -> Bool {
  match (left, right) {
    (None, None) => true
    (Some(a), Some(b)) => graphs_equal(a, b)
    _ => false
  }
}

///|
fn nodes_equal(left : Node, right : Node) -> Bool {
  left.id == right.id &&
  left.description == right.description &&
  data_equal(left.data, right.data) &&
  ports_equal(left.ports, right.ports) &&
  optional_graphs_equal(left.graph, right.graph) &&
  locators_equal(left.locator, right.locator) &&
  attributes_equal(left.extra, right.extra)
}

///|
fn edges_equal(
  left : Edge,
  right : Edge,
  left_graph : Graph,
  right_graph : Graph,
) -> Bool {
  left.id == right.id &&
  left.source == right.source &&
  left.target == right.target &&
  left.source_port == right.source_port &&
  left.target_port == right.target_port &&
  left.effective_direction(left_graph) == right.effective_direction(right_graph) &&
  left.description == right.description &&
  data_equal(left.data, right.data) &&
  optional_graphs_equal(left.graph, right.graph) &&
  attributes_equal(left.extra, right.extra)
}

///|
fn hyperedges_equal(left : Hyperedge, right : Hyperedge) -> Bool {
  if left.id != right.id ||
    left.description != right.description ||
    !data_equal(left.data, right.data) ||
    !attributes_equal(left.extra, right.extra) ||
    !optional_graphs_equal(left.graph, right.graph) ||
    left.endpoints.length() != right.endpoints.length() {
    return false
  }
  for i = 0; i < left.endpoints.length(); i = i + 1 {
    let a = left.endpoints[i]
    let b = right.endpoints[i]
    if a.id != b.id ||
      a.node != b.node ||
      a.port != b.port ||
      a.kind != b.kind ||
      a.description != b.description ||
      !attributes_equal(a.extra, b.extra) {
      return false
    }
  }
  true
}

///|
fn graphs_equal(left : Graph, right : Graph) -> Bool {
  if left.id != right.id ||
    left.edge_default != right.edge_default ||
    left.description != right.description ||
    !data_equal(left.data, right.data) ||
    !locators_equal(left.locator, right.locator) ||
    !attributes_equal(left.extra, right.extra) ||
    left.nodes.length() != right.nodes.length() ||
    left.edges.length() != right.edges.length() ||
    left.hyperedges.length() != right.hyperedges.length() {
    return false
  }
  for i = 0; i < left.nodes.length(); i = i + 1 {
    if !nodes_equal(left.nodes[i], right.nodes[i]) {
      return false
    }
  }
  for i = 0; i < left.edges.length(); i = i + 1 {
    if !edges_equal(left.edges[i], right.edges[i], left, right) {
      return false
    }
  }
  for i = 0; i < left.hyperedges.length(); i = i + 1 {
    if !hyperedges_equal(left.hyperedges[i], right.hyperedges[i]) {
      return false
    }
  }
  true
}

///|
/// Model equivalence ignores key/data declaration ordering, attribute order and XML prefixes.
/// Node/edge/port/endpoint and top-level graph ordinals remain significant for stable addressing.
/// This is not graph isomorphism or XML C14N. Explicit data and omitted defaults remain distinct.
pub fn Document::equivalent(self : Document, other : Document) -> Bool {
  if self.description != other.description ||
    !attributes_equal(self.extra, other.extra) ||
    !data_equal(self.data, other.data) ||
    self.keys.length() != other.keys.length() ||
    self.graphs.length() != other.graphs.length() {
    return false
  }
  let catalog = key_map(self.keys)
  for key in other.keys {
    let original = match catalog.get(key.id) {
      Some(value) => value
      None => return false
    }
    if original.scope != key.scope ||
      original.name != key.name ||
      original.value_type != key.value_type ||
      original.description != key.description ||
      !optional_values_equal(original.default_value, key.default_value) ||
      !attributes_equal(original.extra, key.extra) {
      return false
    }
  }
  for i = 0; i < self.graphs.length(); i = i + 1 {
    if !graphs_equal(self.graphs[i], other.graphs[i]) {
      return false
    }
  }
  true
}
