///|
/// Reference tools emit some non-XSD scalar spellings; tolerance must be explicitly requested.
pub(all) enum ReadProfile {
  Strict
  ReferenceLibraries
} derive(Eq, @debug.Debug)

///|
pub extend ReadProfile with Eq::{equal, not_equal}

///|
pub extend ReadProfile with @debug.Debug::{to_repr}

///|
fn reference_lexical(kind : String?, input : String) -> String {
  let token = input.trim(chars=" \t\r\n").to_owned()
  match (kind, token) {
    (Some("boolean"), "True") => "true"
    (Some("boolean"), "False") => "false"
    (Some("float" | "double"), "inf") => "INF"
    (Some("float" | "double"), "-inf") => "-INF"
    (Some("float" | "double"), "nan") => "NaN"
    _ => input
  }
}

///|
fn normalize_reference_element(
  element : XmlElementValue,
  kinds : Map[String, String],
  default_kind : String?,
) -> Unit raise GraphError {
  if element.namespace_uri != Some(GRAPHML_URI) {
    return
  }
  let kind = match element.name {
    "data" =>
      match attribute_value(element, "key") {
        Some(id) => kinds.get(id)
        None => None
      }
    "default" => default_kind
    _ => None
  }
  if kind is Some(_) && element.content.all(fn(value) { value is Text(_) }) {
    let original = element_text(element)
    let normalized = reference_lexical(kind, original)
    if normalized != original {
      element.content.clear()
      element.content.push(Text(normalized))
    }
  }
  // XML extension payloads and string values are opaque, even if they use GraphML names.
  if element.name == "data" || element.name == "default" {
    return
  }
  let next_default = if element.name == "key" {
    attribute_value(element, "attr.type")
  } else {
    None
  }
  for value in element.content {
    if value is Element(child) {
      normalize_reference_element(child, kinds, next_default)
    }
  }
}

///|
fn normalize_reference_tree(root : XmlElementValue) -> Unit raise GraphError {
  let kinds : Map[String, String] = Map([])
  for child in element_children(root) {
    if child.namespace_uri == Some(GRAPHML_URI) && child.name == "key" {
      if attribute_value(child, "id") is Some(id) &&
        attribute_value(child, "attr.type") is Some(kind) {
        kinds[id] = kind
      }
    }
  }
  normalize_reference_element(root, kinds, None)
}
