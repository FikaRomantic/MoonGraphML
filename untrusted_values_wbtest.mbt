///|
test "unpaired UTF16 is a recoverable graph error instead of encoding panic" {
  let high = b"\x00\xD8".to_unchecked_string()
  let low = b"\x00\xDC".to_unchecked_string()
  for bad in [high, low] {
    assert_true(
      try {
        let _ = utf8_size(bad)
        false
      } catch {
        InvalidGraph(path="xml.unicode", ..) => true
        _ => false
      },
    )
    assert_true(
      try {
        let _ = Key::new(bad, All, StringValue)
        false
      } catch {
        _ => true
      },
    )
    assert_true(
      try {
        let _ = parse(
          "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><desc>" +
          bad +
          "</desc></graphml>",
        )
        false
      } catch {
        _ => true
      },
    )
    let output = Output::new(Limits::default())
    assert_true(
      try {
        output.escaped(bad, false)
        false
      } catch {
        _ => true
      },
    )
  }
  assert_eq(try! utf8_size("Aé中😀"), 10)
}

///|
test "scoped attributes reject cyclic and oversized raw XML before detaching" {
  let doc = try! parse(
    "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><key id=\"k\"/></graphml>",
  )
  let element : XmlElementValue = {
    namespace_uri: None,
    name: "cycle",
    prefix: None,
    namespaces: [],
    attributes: [],
    content: [],
  }
  element.content.push(Element(element))
  let datum : Datum = {
    key: "k",
    id: None,
    value: XmlPayload([Element(element)]),
    extra: [],
    namespaces: [],
  }
  assert_true(
    try {
      let _ = Attributes::new(doc, NodeScope, [datum])
      false
    } catch {
      LimitExceeded(..) => true
      _ => false
    },
  )
  assert_true(
    try {
      let _ = Attributes::new(
        doc,
        NodeScope,
        [Datum::new("k", TextValue("123456"))],
        limits={ ..Limits::default(), text_bytes: 5, },
      )
      false
    } catch {
      LimitExceeded(..) => true
      _ => false
    },
  )
}
