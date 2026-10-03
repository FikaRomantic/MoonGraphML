///|
priv struct Output {
  buffer : StringBuilder
  limit : Int
  depth_limit : Int
  mut bytes : Int
  stack : Array[String]
}

///|
fn Output::new(limits : Limits) -> Output {
  {
    buffer: StringBuilder(),
    limit: limits.output_bytes,
    depth_limit: limits.xml_depth,
    bytes: 0,
    stack: [],
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
) -> Unit raise GraphError {
  valid_local_name(name)
  check_bound("output_depth", self.stack.length() + 1, self.depth_limit)
  self.raw("<\{name}")
  if default_ns is Some(uri) {
    self.attribute("xmlns", uri)
  }
  let prefixes : Map[String, String] = Map([])
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
        let prefix = match prefixes.get(uri) {
          Some(value) => value
          None => {
            let value = "a\{prefixes.length()}"
            prefixes[uri] = value
            self.attribute("xmlns:\{value}", uri)
            value
          }
        }
        "\{prefix}:\{attribute.name}"
      }
    }
    self.attribute(qualified, attribute.value)
  }
  self.raw(">")
  self.stack.push(name)
}

///|
fn Output::end(self : Output, name : String) -> Unit raise GraphError {
  require(
    self.stack.last() == Some(name),
    "xml.output",
    "unbalanced output structure",
  )
  let _ = self.stack.pop()
  self.raw("</\{name}>")
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
        output.start(
          element.name,
          element.attributes,
          default_ns=element.namespace_uri.unwrap_or(""),
        )
        write_xml_values(output, element.content)
        output.end(element.name)
      }
    }
  }
}
