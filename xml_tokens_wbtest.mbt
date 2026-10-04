///|
test "NMTOKEN attributes use Schema whitespace collapse without touching string data" {
  let doc = try! parse(
    "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><key id=\" k \" for=\" node \" attr.type=\" string \" attr.name=\" label \"/><graph id=\" G \" edgedefault=\" directed \"><node id=\" a \" ><data key=\" k \"> a b </data><port name=\" p \"/></node><edge source=\" a \" target=\" a \" sourceport=\" p \"/></graph></graphml>",
  )
  assert_eq(doc.keys()[0].id, "k")
  assert_eq(doc.keys()[0].name, Some("label"))
  assert_eq(doc.graphs()[0].nodes[0].id, "a")
  assert_eq(doc.graphs()[0].edges[0].source_port, Some("p"))
  assert_true(
    doc.graphs()[0].nodes[0].data[0].value is ScalarValue(TextValue(" a b ")),
  )
  assert_true(
    try {
      let _ = Key::new("k", All, StringValue, name="invalid name")
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = parse(
        "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><graph edgedefault=\"directed\"><node id=\"a b\"/></graph></graphml>",
      )
      false
    } catch {
      _ => true
    },
  )
}
