///|
const GRAPHML_URI : String = "http://graphml.graphdrawing.org/xmlns"

///|
fn graphml_element(
  element : XmlElementValue,
  expected : String,
) -> Unit raise GraphError {
  require(
    element.namespace_uri == Some(GRAPHML_URI) && element.name == expected,
    expected,
    "expected GraphML namespace element",
  )
}

///|
fn extra_attributes(
  element : XmlElementValue,
  known : Array[String],
) -> Array[XmlAttributeValue] {
  element.attributes.filter(fn(attribute) {
    !(attribute.namespace_uri is None && known.contains(attribute.name))
  })
}

///|
fn read_payload(
  element : XmlElementValue,
  kind : ValueType?,
) -> DataValue raise GraphError {
  let has_xml = element.content.any(fn(value) { value is Element(_) })
  if has_xml {
    require(kind is None, element.name, "typed scalar contains extension XML")
    XmlPayload(element.content.copy())
  } else {
    ScalarValue(
      Scalar::parse(kind.unwrap_or(StringValue), element_text(element)),
    )
  }
}

///|
fn read_key(element : XmlElementValue) -> Key raise GraphError {
  graphml_element(element, "key")
  let id = required_attribute(element, "id")
  valid_token(id, "key.id")
  let name = attribute_value(element, "attr.name")
  if name is Some(value) {
    valid_token(value, "key.attr.name")
  }
  let scope = Scope::from_name(attribute_value(element, "for").unwrap_or("all"))
  let value_type = match attribute_value(element, "attr.type") {
    Some(name) => Some(ValueType::from_name(name))
    None => None
  }
  let mut description : String? = None
  let mut default_value : DataValue? = None
  let mut default_extra : Array[XmlAttributeValue] = []
  let mut default_namespaces : Array[NamespaceBinding] = []
  for child in element_children(element) {
    require(
      child.namespace_uri == Some(GRAPHML_URI),
      "key",
      "unknown child namespace",
    )
    match child.name {
      "desc" => {
        require(
          description is None && default_value is None,
          "key.desc",
          "duplicate or misplaced description",
        )
        description = Some(element_text(child))
      }
      "default" => {
        require(default_value is None, "key.default", "duplicate default")
        default_value = Some(read_payload(child, value_type))
        default_extra = child.attributes.copy()
        default_namespaces = child.namespaces.copy()
      }
      _ => raise Unsupported(path="key", feature=child.name)
    }
  }
  {
    id,
    scope,
    name,
    value_type,
    default_value,
    default_extra,
    default_namespaces,
    description,
    extra: extra_attributes(element, ["id", "for", "attr.name", "attr.type"]),
    namespaces: element.namespaces,
  }
}

///|
fn read_keys(
  root : XmlElementValue,
  limits : Limits,
) -> Array[Key] raise GraphError {
  graphml_element(root, "graphml")
  let keys : Array[Key] = []
  let ids : Map[String, Bool] = Map([])
  let mut saw_content = false
  let mut saw_description = false
  for child in element_children(root) {
    require(
      child.namespace_uri == Some(GRAPHML_URI),
      "graphml",
      "unknown child namespace",
    )
    match child.name {
      "desc" => {
        require(
          !saw_description && !saw_content && keys.is_empty(),
          "graphml.desc",
          "duplicate or misplaced description",
        )
        let _ = element_text(child)
        saw_description = true
      }
      "key" => {
        require(
          !saw_content,
          "graphml.key",
          "keys must precede graphs and data",
        )
        check_bound("keys", keys.length() + 1, limits.keys)
        let key = read_key(child)
        require(!ids.contains(key.id), "key.id", "duplicate key \{key.id}")
        ids[key.id] = true
        keys.push(key)
      }
      "graph" | "data" => saw_content = true
      _ => raise Unsupported(path="graphml", feature=child.name)
    }
  }
  keys
}

///|
pub fn inspect_keys(
  input : String,
  limits? : Limits = Limits::default(),
) -> Array[Key] raise GraphError {
  let root = read_tree(input, limits)
  normalize_graphml_tokens(root)
  read_keys(root, limits)
}

///|
fn key_map(keys : Array[Key]) -> Map[String, Key] {
  let result : Map[String, Key] = Map([])
  for key in keys {
    result[key.id] = key
  }
  result
}

///|
fn read_datum(
  element : XmlElementValue,
  keys : Map[String, Key],
) -> Datum raise GraphError {
  graphml_element(element, "data")
  let id = attribute_value(element, "id")
  if id is Some(value) {
    valid_token(value, "data.id")
  }
  let key_id = required_attribute(element, "key")
  let key = match keys.get(key_id) {
    Some(value) => value
    None =>
      raise InvalidGraph(path="data.key", reason="undefined key \{key_id}")
  }
  {
    key: key_id,
    id,
    value: read_payload(element, key.value_type),
    extra: extra_attributes(element, ["id", "key"]),
    namespaces: element.namespaces,
  }
}
