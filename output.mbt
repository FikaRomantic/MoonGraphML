///|
priv struct Output {
  buffer : StringBuilder
  limit : Int
  depth_limit : Int
  attribute_limit : Int
  text_limit : Int
  mut bytes : Int
  mut attribute_count : Int
  stack : Array[String]
  qualified_names : Array[String]
  namespace_scopes : Array[Array[NamespaceBinding]]
  text_sizes : Array[Int]
}

///|
fn Output::new(limits : Limits) -> Output {
  {
    buffer: StringBuilder(),
    limit: limits.output_bytes,
    depth_limit: limits.xml_depth,
    attribute_limit: limits.attributes_per_element,
    text_limit: limits.text_bytes,
    bytes: 0,
    attribute_count: 0,
    stack: [],
    qualified_names: [],
    namespace_scopes: [],
    text_sizes: [],
  }
}

///|
fn Output::reserve(self : Output, amount : Int) -> Unit raise GraphError {
  if amount < 0 || amount > self.limit - self.bytes {
    raise LimitExceeded(resource="output_bytes", limit=self.limit)
  }
  self.bytes = self.bytes + amount
}

///|
fn Output::raw(self : Output, text : String) -> Unit raise GraphError {
  self.reserve(utf8_size(text))
  self.buffer.write_string(text)
}

///|
fn Output::escaped(
  self : Output,
  text : String,
  attribute : Bool,
) -> Unit raise GraphError {
  let size = utf8_size(text)
  if attribute {
    check_bound("attribute_bytes", size, self.text_limit)
  } else {
    let previous = self.text_sizes.last().unwrap_or(0)
    if size > self.text_limit - previous {
      raise LimitExceeded(resource="text_bytes", limit=self.text_limit)
    }
    if !self.text_sizes.is_empty() {
      self.text_sizes[self.text_sizes.length() - 1] = previous + size
    }
  }
  for ch in text {
    let c = ch.to_int()
    require(
      c == 9 ||
      c == 10 ||
      c == 13 ||
      (c >= 32 && c <= 0xD7FF) ||
      (c >= 0xE000 && c <= 0xFFFD) ||
      (c >= 0x10000 && c <= 0x10FFFF),
      "xml.output",
      "illegal XML character",
    )
    match ch {
      '&' => self.raw("&amp;")
      '<' => self.raw("&lt;")
      '>' => self.raw("&gt;")
      '"' => if attribute { self.raw("&quot;") } else { self.raw("\"") }
      '\r' => self.raw("&#13;")
      '\n' => if attribute { self.raw("&#10;") } else { self.raw("\n") }
      '\t' => if attribute { self.raw("&#9;") } else { self.raw("\t") }
      _ => {
        self.reserve(
          if c < 128 {
            1
          } else if c < 2048 {
            2
          } else if c < 65536 {
            3
          } else {
            4
          },
        )
        self.buffer.write_char(ch)
      }
    }
  }
}

///|
fn valid_local_name(name : String) -> Unit raise GraphError {
  valid_token(name, "xml.name")
  require(!name.contains(":"), "xml.name", "local name must not contain colon")
  let first = name.to_array()[0].to_int()
  require(
    !(first >= 48 && first <= 57) &&
    first != 45 &&
    first != 46 &&
    first != 0xB7 &&
    !(first >= 0x300 && first <= 0x36F) &&
    !(first >= 0x203F && first <= 0x2040),
    "xml.name",
    "invalid first name character",
  )
}

///|
fn Output::attribute(
  self : Output,
  name : String,
  value : String,
) -> Unit raise GraphError {
  check_bound(
    "attributes_per_element",
    self.attribute_count + 1,
    self.attribute_limit,
  )
  self.attribute_count = self.attribute_count + 1
  self.raw(" \{name}=\"")
  self.escaped(value, true)
  self.raw("\"")
}

///|
fn Output::start(
  self : Output,
  name : String,
  attributes : Array[XmlAttributeValue],
  default_ns? : String,
  prefix? : String,
  namespaces? : Array[NamespaceBinding] = [],
) -> Unit raise GraphError {
  valid_local_name(name)
  self.attribute_count = 0
  check_bound("output_depth", self.stack.length() + 1, self.depth_limit)
  let inherited = match self.namespace_scopes.last() {
    Some(scope) => scope
    None => base_namespaces()
  }
  let changes_scope = namespaces.any(fn(binding) {
      namespace_uri_for(inherited, binding.prefix) !=
      Some(binding.namespace_uri)
    }) ||
    default_ns
    .map(fn(uri) { namespace_uri_for(inherited, None) != Some(uri) })
    .unwrap_or(false) ||
    attributes.any(fn(attribute) {
      attribute.namespace_uri is Some(uri) &&
      uri != "http://www.w3.org/XML/1998/namespace"
    })
  let scope = if changes_scope { inherited.copy() } else { inherited }
  let declarations : Array[NamespaceBinding] = []
  let seen : Map[String?, Bool] = Map([])
  for binding in namespaces {
    validate_namespace_binding(binding)
    require(
      !seen.contains(binding.prefix),
      "xml.namespace",
      "duplicate prefix binding",
    )
    seen[binding.prefix] = true
    if namespace_uri_for(scope, binding.prefix) != Some(binding.namespace_uri) {
      declarations.push(binding)
      set_namespace_binding(scope, binding.prefix, binding.namespace_uri)
    }
  }
  if default_ns is Some(uri) {
    let binding : NamespaceBinding = { prefix: None, namespace_uri: uri, }
    validate_namespace_binding(binding)
    if namespace_uri_for(scope, None) != Some(uri) {
      set_namespace_binding(declarations, None, uri)
      set_namespace_binding(scope, None, uri)
    }
  }
  let qualified_name = match prefix {
    Some(value) => {
      valid_local_name(value)
      require(
        value != "xmlns" && namespace_uri_for(scope, prefix) is Some(_),
        "xml.namespace",
        "unbound element prefix",
      )
      "\{value}:\{name}"
    }
    None => name
  }
  self.raw("<\{qualified_name}")
  for binding in declarations {
    let declaration = match binding.prefix {
      Some(value) => "xmlns:\{value}"
      None => "xmlns"
    }
    self.attribute(declaration, binding.namespace_uri)
  }
  let names : Map[(String?, String), Bool] = Map([])
  for attribute in attributes {
    valid_local_name(attribute.name)
    let expanded = (attribute.namespace_uri, attribute.name)
    require(
      !names.contains(expanded),
      "xml.attribute",
      "duplicate expanded attribute name",
    )
    names[expanded] = true
    let qualified = match attribute.namespace_uri {
      None => {
        require(
          attribute.name != "xmlns",
          "xml.attribute",
          "namespace declaration is not a data attribute",
        )
        attribute.name
      }
      Some("http://www.w3.org/XML/1998/namespace") => "xml:\{attribute.name}"
      Some(uri) => {
        require(
          uri != "http://www.w3.org/2000/xmlns/" && uri != "",
          "xml.attribute",
          "invalid attribute namespace",
        )
        let existing = scope.search_by(fn(binding) {
          binding.prefix is Some(_) && binding.namespace_uri == uri
        })
        let chosen = match existing {
          Some(index) => scope[index].prefix.unwrap()
          None => {
            let mut index = 0
            while namespace_uri_for(scope, Some("a\{index}")) is Some(_) {
              index = index + 1
            }
            let value = "a\{index}"
            set_namespace_binding(scope, Some(value), uri)
            self.attribute("xmlns:\{value}", uri)
            value
          }
        }
        "\{chosen}:\{attribute.name}"
      }
    }
    self.attribute(qualified, attribute.value)
  }
  self.raw(">")
  self.stack.push(name)
  self.qualified_names.push(qualified_name)
  self.namespace_scopes.push(scope)
  self.text_sizes.push(0)
}

///|
/// Preserve a GraphML container's QName value context without changing its element namespace.
fn Output::graphml_start(
  self : Output,
  name : String,
  attributes : Array[XmlAttributeValue],
  namespaces? : Array[NamespaceBinding] = [],
) -> Unit raise GraphError {
  let inherited = match self.namespace_scopes.last() {
    Some(scope) => scope
    None => {
      let scope = base_namespaces()
      set_namespace_binding(scope, None, GRAPHML_URI)
      scope
    }
  }
  let scope = if namespaces.is_empty() { inherited } else { namespaces }
  if namespace_uri_for(scope, None) == Some(GRAPHML_URI) {
    self.start(name, attributes, namespaces=scope)
    return
  }
  match
    scope.search_by(fn(binding) {
      binding.prefix is Some(_) && binding.namespace_uri == GRAPHML_URI
    }) {
    Some(index) =>
      self.start(
        name,
        attributes,
        prefix?=scope[index].prefix,
        namespaces=scope,
      )
    None => {
      let context = scope.copy()
      let mut index = 0
      while namespace_uri_for(context, Some("gml\{index}")) is Some(_) {
        index = index + 1
      }
      let prefix = "gml\{index}"
      context.push({ prefix: Some(prefix), namespace_uri: GRAPHML_URI, })
      self.start(name, attributes, prefix~, namespaces=context)
    }
  }
}

///|
fn Output::end(self : Output, name : String) -> Unit raise GraphError {
  require(
    self.stack.last() == Some(name),
    "xml.output",
    "unbalanced output structure",
  )
  let _ = self.stack.pop()
  let qualified = self.qualified_names.pop().unwrap()
  let _ = self.namespace_scopes.pop()
  let _ = self.text_sizes.pop()
  self.raw("</\{qualified}>")
}

///|
fn Output::finish(self : Output) -> String raise GraphError {
  require(self.stack.is_empty(), "xml.output", "unfinished output structure")
  self.buffer.to_string()
}

///|
fn plain_attribute(name : String, value : String) -> XmlAttributeValue {
  { namespace_uri: None, name, value, }
}

///|
fn optional_attribute(
  attributes : Array[XmlAttributeValue],
  name : String,
  value : String?,
) -> Unit {
  if value is Some(text) {
    attributes.push(plain_attribute(name, text))
  }
}

///|
fn write_xml_values(
  output : Output,
  content : Array[XmlValue],
) -> Unit raise GraphError {
  for value in content {
    match value {
      Text(text) => output.escaped(text, false)
      Element(element) => {
        require(
          element.namespace_uri != Some(""),
          "xml.namespace",
          "use None for an unnamespaced element",
        )
        let prefix = if element.namespace_uri ==
          Some("http://www.w3.org/XML/1998/namespace") {
          Some("xml")
        } else {
          element.prefix
        }
        let namespaces = element.namespaces.copy()
        if prefix is Some(value) {
          let uri = element.namespace_uri.unwrap_or_else(() => {
            raise InvalidGraph(
              path="xml.namespace",
              reason="prefixed element has no namespace",
            )
          })
          match namespace_uri_for(namespaces, prefix) {
            Some(bound) =>
              require(
                bound == uri,
                "xml.namespace",
                "element prefix binding disagrees with expanded name",
              )
            None => set_namespace_binding(namespaces, Some(value), uri)
          }
        } else {
          let uri = element.namespace_uri.unwrap_or("")
          match namespace_uri_for(namespaces, None) {
            Some(bound) =>
              require(
                bound == uri,
                "xml.namespace",
                "default binding disagrees with expanded name",
              )
            None => set_namespace_binding(namespaces, None, uri)
          }
        }
        output.start(element.name, element.attributes, prefix?, namespaces~)
        write_xml_values(output, element.content)
        output.end(element.name)
      }
    }
  }
}
