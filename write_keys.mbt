///|
fn write_description(
  output : Output,
  description : String?,
) -> Unit raise GraphError {
  if description is Some(text) {
    output.start("desc", [])
    output.escaped(text, false)
    output.end("desc")
  }
}

///|
fn write_payload(output : Output, value : DataValue) -> Unit raise GraphError {
  match value {
    ScalarValue(scalar) => output.escaped(scalar.lexical(), false)
    XmlPayload(content) => write_xml_values(output, content)
  }
}

///|
fn write_data(output : Output, data : Array[Datum]) -> Unit raise GraphError {
  for datum in data {
    let attributes = [plain_attribute("key", datum.key)]
    optional_attribute(attributes, "id", datum.id)
    attributes.append(datum.extra)
    output.start("data", attributes)
    write_payload(output, datum.value)
    output.end("data")
  }
}

///|
fn write_key(output : Output, key : Key) -> Unit raise GraphError {
  let attributes = [
    plain_attribute("id", key.id),
    plain_attribute("for", key.scope.name()),
  ]
  optional_attribute(attributes, "attr.name", key.name)
  if key.value_type is Some(kind) {
    attributes.push(plain_attribute("attr.type", kind.name()))
  }
  attributes.append(key.extra)
  output.start("key", attributes)
  write_description(output, key.description)
  if key.default_value is Some(value) {
    output.start("default", [])
    write_payload(output, value)
    output.end("default")
  }
  output.end("key")
}
