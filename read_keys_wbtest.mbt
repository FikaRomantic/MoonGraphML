///|
test "key inspection parses typed defaults and uses ids rather than names" {
  let keys = try! inspect_keys(
    "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><key id='d0' for='node' attr.name='enabled' attr.type='boolean'><default>1</default></key></graphml>",
  )
  assert_eq(keys.length(), 1)
  assert_eq(keys[0].id, "d0")
  assert_eq(keys[0].name, Some("enabled"))
  assert_true(keys[0].default_value is Some(ScalarValue(BooleanValue(true))))
}

///|
test "duplicate keys, namespace spoofing and key order fail" {
  for
    body in [
      "<key id='d'/><key id='d'/>", "<graph edgedefault='directed'/><key id='d'/>",
      "<key xmlns='urn:fake' id='d'/>",
    ] {
    let xml = "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'>\{body}</graphml>"
    assert_true(
      try {
        let _ = inspect_keys(xml)
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "untyped keys retain extension XML including inherited namespaces" {
  let keys = try! inspect_keys(
    "<graphml xmlns='http://graphml.graphdrawing.org/xmlns' xmlns:y='urn:style'><key id='d'><default><y:Shape color='blue'/></default></key></graphml>",
  )
  guard keys[0].default_value is Some(XmlPayload(content)) else {
    abort("expected extension payload")
  }
  guard content[0] is Element(element) else { abort("expected element") }
  assert_eq(element.namespace_uri, Some("urn:style"))
}
