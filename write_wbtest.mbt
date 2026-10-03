///|
test "deterministic GraphML roundtrip preserves advanced structure" {
  let input = "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><key id=\"k\" for=\"node\" attr.type=\"string\"><default>中文 &amp; 😀</default></key><graph id=\"G\" edgedefault=\"directed\"><node id=\"a\"><data key=\"k\">a&#13;b</data><port name=\"p\"><port name=\"q\"/></port><graph id=\"inner\" edgedefault=\"undirected\"><node id=\"b\"/></graph></node><edge source=\"a\" target=\"b\" sourceport=\"q\" directed=\"false\"/><hyperedge id=\"h\"><endpoint node=\"a\" type=\"out\"/><endpoint node=\"b\" type=\"in\"/></hyperedge></graph></graphml>"
  let first = try! serialize(parse(input))
  let second = try! serialize(parse(first))
  assert_eq(first, second)
  let doc = try! parse(second)
  assert_eq(doc.graphs[0].edges[0].directed, Some(false))
  assert_eq(
    doc.graphs[0].nodes[0].data[0].value is ScalarValue(TextValue("a\rb")),
    true,
  )
  assert_eq(doc.graphs[0].hyperedges[0].endpoints[1].kind, In)
}

///|
test "extension payload and XLink locator retain expanded names" {
  let input = "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\" xmlns:e=\"urn:custom\" xmlns:x=\"http://www.w3.org/1999/xlink\"><key id=\"k\"/><data key=\"k\"><e:shape e:title=\"a&#10;b\"><empty xmlns=\"\"/></e:shape></data><graph edgedefault=\"directed\"><locator x:href=\"https://example.invalid/no-fetch\" x:type=\"simple\"/></graph></graphml>"
  let doc = try! parse(serialize(parse(input)))
  guard doc.data[0].value is XmlPayload(content) else {
    abort("lost extension")
  }
  guard content[0] is Element(element) else { abort("lost element") }
  assert_eq(element.namespace_uri, Some("urn:custom"))
  assert_eq(element.attributes[0].value, "a\nb")
  assert_eq(doc.graphs[0].locator.unwrap().link_type, Some("simple"))
}

///|
test "serialization fails rather than returning truncated output" {
  let doc = try! parse(
    "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><graph edgedefault=\"undirected\"/></graphml>",
  )
  assert_true(
    try {
      let _ = serialize(doc, limits={ ..Limits::default(), output_bytes: 20, })
      false
    } catch {
      LimitExceeded(..) => true
      _ => false
    },
  )
}
