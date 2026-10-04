///|
fn referenced_prefixes(text : String, names : Map[String?, Bool]) -> Unit {
  let mut token = StringBuilder()
  for ch in text {
    if ch == ':' {
      let prefix = token.to_string()
      let valid = try {
        valid_local_name(prefix)
        true
      } catch {
        _ => false
      }
      if valid {
        names[Some(prefix)] = true
      }
      token = StringBuilder()
    } else if xml_name_char(ch.to_int()) {
      token.write_char(ch)
    } else {
      token = StringBuilder()
    }
  }
}

///|
/// Namespace declarations themselves are not data, but prefixes occurring in opaque values
/// retain their bindings. This is deliberately conservative without claiming XSD validation.
fn namespace_references(
  attributes : Array[XmlAttributeValue],
  content : Array[XmlValue],
) -> Map[String?, Bool] {
  let names : Map[String?, Bool] = Map([])
  for attribute in attributes {
    referenced_prefixes(attribute.value, names)
    if attribute.namespace_uri ==
      Some("http://www.w3.org/2001/XMLSchema-instance") &&
      attribute.name == "type" &&
      !attribute.value.contains(":") {
      names[None] = true
    }
  }
  for value in content {
    if value is Text(text) {
      referenced_prefixes(text, names)
    }
  }
  names
}

///|
fn namespace_context_equal(
  left : Array[NamespaceBinding],
  right : Array[NamespaceBinding],
  attributes : Array[XmlAttributeValue],
  content : Array[XmlValue],
) -> Bool {
  let names = namespace_references(attributes, content)
  for (prefix, _) in names {
    let left_uri = namespace_uri_for(left, prefix).unwrap_or("")
    let right_uri = namespace_uri_for(right, prefix).unwrap_or("")
    if left_uri != right_uri {
      return false
    }
  }
  true
}

///|
fn value_namespace_content(value : DataValue?) -> Array[XmlValue] {
  match value {
    Some(ScalarValue(TextValue(text))) => [Text(text)]
    Some(XmlPayload(content)) => content
    _ => []
  }
}

///|
fn default_context_equal(left : Key, right : Key) -> Bool {
  namespace_context_equal(
    left.default_namespaces,
    right.default_namespaces,
    left.default_extra,
    value_namespace_content(left.default_value),
  )
}
