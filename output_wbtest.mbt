///|
test "writer preserves attribute whitespace and resets extension namespaces" {
  let output = Output::new(Limits::default())
  output.start(
    "root",
    [plain_attribute("v", "a\n\t\rb")],
    default_ns=GRAPHML_URI,
  )
  write_xml_values(output, [
    Element({
      namespace_uri: None,
      name: "custom",
      attributes: [],
      content: [Text("<&\r")],
    }),
  ])
  output.end("root")
  let tree = try! read_tree(output.finish(), Limits::default())
  assert_eq(attribute_value(tree, "v"), Some("a\n\t\rb"))
  guard tree.content[0] is Element(element) else { abort("extension missing") }
  assert_eq(element.namespace_uri, None)
  assert_eq(try! element_text(element), "<&\r")
}

///|
test "writer tracks escaped Unicode bytes and rejects control characters" {
  let limits = { ..Limits::default(), output_bytes: 5, }
  let output = Output::new(limits)
  try! output.escaped("😀", false)
  assert_eq(output.bytes, 4)
  assert_true(
    try {
      output.escaped("&", false)
      false
    } catch {
      LimitExceeded(..) => true
      _ => false
    },
  )
  assert_true(
    try {
      Output::new(Limits::default()).escaped("\u0000", false)
      false
    } catch {
      _ => true
    },
  )
}
