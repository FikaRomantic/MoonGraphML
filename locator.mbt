///|
const XLINK_URI : String = "http://www.w3.org/1999/xlink"

///|
fn namespaced_attribute(
  element : XmlElementValue,
  uri : String,
  name : String,
) -> String? {
  for attribute in element.attributes {
    if attribute.namespace_uri == Some(uri) && attribute.name == name {
      return Some(attribute.value)
    }
  }
  None
}

///|
fn read_locator(element : XmlElementValue) -> Locator raise GraphError {
  graphml_element(element, "locator")
  require(
    element_children(element).is_empty(),
    "locator",
    "locator must be empty",
  )
  let href = match namespaced_attribute(element, XLINK_URI, "href") {
    Some(value) => value
    None => raise InvalidGraph(path="locator", reason="missing xlink:href")
  }
  let link_type = namespaced_attribute(element, XLINK_URI, "type")
  require(
    link_type is None || link_type == Some("simple"),
    "locator",
    "xlink:type must be simple",
  )
  let extra = element.attributes.filter(fn(attribute) {
    !(attribute.namespace_uri == Some(XLINK_URI) &&
    (attribute.name == "href" || attribute.name == "type"))
  })
  { href, link_type, extra, namespaces: element.namespaces, }
}

///|
fn find_locator(
  children : Array[XmlElementValue],
  owner : String,
) -> Locator? raise GraphError {
  let mut locator : Locator? = None
  for child in children {
    if child.namespace_uri == Some(GRAPHML_URI) && child.name == "locator" {
      require(locator is None, owner, "duplicate locator")
      locator = Some(read_locator(child))
    }
  }
  if locator is Some(_) {
    require(
      children.all(fn(child) { child.name == "desc" || child.name == "locator" }),
      owner,
      "locator cannot coexist with inline structure",
    )
  }
  locator
}
