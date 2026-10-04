///|
/// XML Schema NMTOKEN has whitespace=collapse. Any remaining inner whitespace is invalid.
fn graphml_token_names(name : String) -> Array[String] {
  match name {
    "key" => ["id", "for", "attr.name", "attr.type"]
    "graph" => ["id", "edgedefault"]
    "node" => ["id"]
    "edge" => ["id", "source", "target", "sourceport", "targetport"]
    "hyperedge" => ["id"]
    "endpoint" => ["id", "node", "port", "type"]
    "port" => ["name"]
    "data" => ["id", "key"]
    _ => []
  }
}

///|
/// Normalize only declared GraphML token attributes, never strings or opaque payload content.
fn normalize_graphml_tokens(element : XmlElementValue) -> Unit {
  if element.namespace_uri != Some(GRAPHML_URI) {
    return
  }
  let names = graphml_token_names(element.name)
  for i = 0; i < element.attributes.length(); i = i + 1 {
    let attribute = element.attributes[i]
    if attribute.namespace_uri is None && names.contains(attribute.name) {
      element.attributes[i] = {
        ..attribute,
        value: attribute.value.trim(chars=" \t\r\n").to_owned(),
      }
    }
  }
  if element.name == "data" || element.name == "default" {
    return
  }
  for value in element.content {
    if value is Element(child) {
      normalize_graphml_tokens(child)
    }
  }
}
