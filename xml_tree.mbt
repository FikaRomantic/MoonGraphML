///|
pub(all) struct XmlAttributeValue {
  namespace_uri : String?
  name : String
  value : String
}

///|
/// A prefix binding in scope. None denotes the default namespace; an empty URI resets it.
pub(all) struct NamespaceBinding {
  prefix : String?
  namespace_uri : String
}

///|
pub(all) struct XmlElementValue {
  namespace_uri : String?
  name : String
  prefix : String?
  namespaces : Array[NamespaceBinding]
  attributes : Array[XmlAttributeValue]
  content : Array[XmlValue]
}

///|
pub(all) enum XmlValue {
  Element(XmlElementValue)
  Text(String)
}

///|
fn scan_declarations(input : String) -> Unit raise GraphError {
  let mut position = 0
  while position < input.length() {
    let suffix = input[position:]
    let end_marker = if suffix.has_prefix("<!--") {
      position = position + 4
      Some("-->")
    } else if suffix.has_prefix("<![CDATA[") {
      position = position + 9
      Some("]]>")
    } else if suffix.has_prefix("<?") {
      position = position + 2
      Some("?>")
    } else {
      None
    }
    match end_marker {
      Some(marker) => {
        while position < input.length() && !input[position:].has_prefix(marker) {
          position = position + 1
        }
        position = position + marker.length()
      }
      None => {
        if suffix.has_prefix("<!DOCTYPE") {
          raise Unsupported(
            path="xml",
            feature="DOCTYPE and entity declarations",
          )
        }
        position = position + 1
      }
    }
  }
}

///|
fn base_namespaces() -> Array[NamespaceBinding] {
  [
    { prefix: None, namespace_uri: "", },
    {
      prefix: Some("xml"),
      namespace_uri: "http://www.w3.org/XML/1998/namespace",
    },
  ]
}

///|
fn namespace_uri_for(
  bindings : Array[NamespaceBinding],
  prefix : String?,
) -> String? {
  for binding in bindings {
    if binding.prefix == prefix {
      return Some(binding.namespace_uri)
    }
  }
  None
}

///|
fn set_namespace_binding(
  bindings : Array[NamespaceBinding],
  prefix : String?,
  namespace_uri : String,
) -> Unit {
  for index = 0; index < bindings.length(); index = index + 1 {
    if bindings[index].prefix == prefix {
      bindings[index] = { prefix, namespace_uri, }
      return
    }
  }
  bindings.push({ prefix, namespace_uri, })
}

///|
fn validate_namespace_binding(
  binding : NamespaceBinding,
) -> Unit raise GraphError {
  let _ = utf8_size(binding.namespace_uri)
  if binding.prefix is Some(prefix) {
    valid_local_name(prefix)
    require(prefix != "xmlns", "xml.namespace", "reserved namespace prefix")
    require(
      binding.namespace_uri != "",
      "xml.namespace",
      "prefix cannot be undeclared",
    )
    require(
      (prefix == "xml") ==
      (binding.namespace_uri == "http://www.w3.org/XML/1998/namespace"),
      "xml.namespace",
      "XML namespace must use the xml prefix",
    )
  } else {
    require(
      binding.namespace_uri != "http://www.w3.org/XML/1998/namespace",
      "xml.namespace",
      "XML namespace cannot be the default",
    )
  }
  require(
    binding.namespace_uri != "http://www.w3.org/2000/xmlns/",
    "xml.namespace",
    "reserved namespace URI",
  )
}

///|
fn xml_element(
  element : @xml.NamespaceElement,
  inherited : Array[NamespaceBinding],
) -> XmlElementValue raise GraphError {
  valid_local_name(element.name.local_name)
  if element.name.prefix is Some(prefix) {
    valid_local_name(prefix)
  }
  // Internal parser contexts are immutable; only a declaration creates a new scope.
  let namespaces = if element.namespace_declarations.is_empty() {
    inherited
  } else {
    inherited.copy()
  }
  for declaration in element.namespace_declarations {
    let binding : NamespaceBinding = {
      prefix: declaration.prefix,
      namespace_uri: declaration.namespace_uri,
    }
    validate_namespace_binding(binding)
    set_namespace_binding(namespaces, binding.prefix, binding.namespace_uri)
  }
  let attributes : Array[XmlAttributeValue] = []
  for attribute in element.attributes {
    valid_local_name(attribute.name.local_name)
    if attribute.name.prefix is Some(prefix) {
      valid_local_name(prefix)
    }
    attributes.push({
      namespace_uri: attribute.name.namespace_uri,
      name: attribute.name.local_name,
      value: attribute.value,
    })
  }
  {
    namespace_uri: element.name.namespace_uri,
    name: element.name.local_name,
    prefix: element.name.prefix,
    namespaces,
    attributes,
    content: [],
  }
}

///|
fn read_tree(
  input : String,
  limits : Limits,
) -> XmlElementValue raise GraphError {
  limits.validate()
  check_bound("input_bytes", input.length(), limits.input_bytes)
  check_bound("input_bytes", utf8_size(input), limits.input_bytes)
  scan_declarations(input)
  let reader = @xml.NamespaceReader::from_string(input)
  let stack : Array[XmlElementValue] = []
  let text_sizes : Array[Int32] = []
  let mut root : XmlElementValue? = None
  let mut events = 0
  while true {
    let event = reader.read_event() catch {
      error => raise InvalidXml(error.to_string())
    }
    if event.kind is Eof {
      break
    }
    check_bound("xml_events", events + 1, limits.xml_elements)
    events = events + 1
    match event.kind {
      Start(element) | Empty(element) => {
        check_bound("xml_depth", stack.length() + 1, limits.xml_depth)
        check_bound(
          "attributes_per_element",
          element.attributes.length() + element.namespace_declarations.length(),
          limits.attributes_per_element,
        )
        let inherited = match stack.last() {
          Some(parent) => parent.namespaces
          None => base_namespaces()
        }
        let parsed = xml_element(element, inherited)
        for declaration in element.namespace_declarations {
          check_bound(
            "namespace_bytes",
            utf8_size(declaration.namespace_uri),
            limits.text_bytes,
          )
        }
        for attribute in parsed.attributes {
          check_bound(
            "attribute_bytes",
            utf8_size(attribute.value),
            limits.text_bytes,
          )
        }
        if stack.is_empty() {
          require(root is None, "xml", "multiple roots")
          root = Some(parsed)
        } else {
          stack[stack.length() - 1].content.push(Element(parsed))
        }
        if event.kind is Start(_) {
          stack.push(parsed)
          text_sizes.push(0)
        }
      }
      End(_) => {
        require(!stack.is_empty(), "xml", "unmatched closing element")
        let _ = stack.pop()
        let _ = text_sizes.pop()
      }
      Text(text) | CData(text) => {
        check_bound("text_bytes", utf8_size(text), limits.text_bytes)
        if stack.is_empty() {
          require(
            text.trim(chars=" \t\r\n").is_empty(),
            "xml",
            "text outside root",
          )
        } else {
          let last = text_sizes.length() - 1
          let amount = utf8_size(text)
          if amount > limits.text_bytes - text_sizes[last] {
            raise LimitExceeded(resource="text_bytes", limit=limits.text_bytes)
          }
          text_sizes[last] = text_sizes[last] + amount
          stack[stack.length() - 1].content.push(Text(text))
        }
      }
      DocType(_) => raise Unsupported(path="xml", feature="DOCTYPE")
      Decl(encoding~, ..) =>
        if encoding is Some(name) {
          require(
            name.to_upper() == "UTF-8",
            "xml.encoding",
            "only UTF-8 is supported",
          )
        }
      Comment(_) => ()
      PI(target~, ..) => valid_local_name(target)
      Eof => ()
    }
  }
  require(stack.is_empty(), "xml", "unclosed elements")
  match root {
    Some(element) => element
    None => raise InvalidXml("missing document root")
  }
}

///|
fn attribute_value(element : XmlElementValue, name : String) -> String? {
  for attribute in element.attributes {
    if attribute.namespace_uri is None && attribute.name == name {
      return Some(attribute.value)
    }
  }
  None
}

///|
fn required_attribute(
  element : XmlElementValue,
  name : String,
) -> String raise GraphError {
  match attribute_value(element, name) {
    Some(value) => value
    None =>
      raise InvalidGraph(path=element.name, reason="missing \{name} attribute")
  }
}

///|
fn element_children(
  element : XmlElementValue,
) -> Array[XmlElementValue] raise GraphError {
  let children = []
  for child in element.content {
    match child {
      Element(value) => children.push(value)
      Text(text) =>
        require(
          text.trim(chars=" \t\r\n").is_empty(),
          element.name,
          "unexpected structural text",
        )
    }
  }
  children
}

///|
fn element_text(element : XmlElementValue) -> String raise GraphError {
  if element.namespace_uri == Some(GRAPHML_URI) && element.name == "desc" {
    require(
      element.attributes.is_empty(),
      "desc",
      "description does not accept attributes",
    )
  }
  let buffer = StringBuilder()
  for child in element.content {
    match child {
      Text(text) => buffer.write_string(text)
      Element(_) =>
        raise InvalidGraph(
          path=element.name,
          reason="unexpected XML in scalar content",
        )
    }
  }
  buffer.to_string()
}
