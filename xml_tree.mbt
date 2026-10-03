///|
pub(all) struct XmlAttributeValue {
  namespace_uri : String?
  name : String
  value : String
}

///|
pub(all) struct XmlElementValue {
  namespace_uri : String?
  name : String
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
fn xml_element(element : @xml.NamespaceElement) -> XmlElementValue {
  {
    namespace_uri: element.name.namespace_uri,
    name: element.name.local_name,
    attributes: element.attributes.map(fn(attribute) {
      {
        namespace_uri: attribute.name.namespace_uri,
        name: attribute.name.local_name,
        value: attribute.value,
      }
    }),
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
          element.attributes.length(),
          limits.attributes_per_element,
        )
        let parsed = xml_element(element)
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
        }
      }
      End(_) => {
        require(!stack.is_empty(), "xml", "unmatched closing element")
        let _ = stack.pop()
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
      Comment(_) | PI(..) => ()
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
