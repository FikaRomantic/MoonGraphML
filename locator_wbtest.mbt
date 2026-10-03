///|
test "external locators are retained without fetching their target" {
  let doc = try! parse(
    "<graphml xmlns='http://graphml.graphdrawing.org/xmlns' xmlns:xlink='http://www.w3.org/1999/xlink'><graph edgedefault='directed'><node id='remote'><locator xlink:href='https://invalid.example/unavailable.graphml'/></node></graph></graphml>",
  )
  guard doc.graphs[0].nodes[0].locator is Some(locator) else {
    abort("missing locator")
  }
  assert_eq(locator.href, "https://invalid.example/unavailable.graphml")
}

///|
test "locator cannot coexist with inline structure or fake namespace href" {
  for
    content in [
      "<node id='a'/><locator xlink:href='remote'/>", "<locator href='remote'/>",
      "<locator xlink:href='remote' xlink:type='extended'/>",
    ] {
    let input = "<graphml xmlns='http://graphml.graphdrawing.org/xmlns' xmlns:xlink='http://www.w3.org/1999/xlink'><graph edgedefault='directed'>\{content}</graph></graphml>"
    assert_true(
      try {
        let _ = parse(input)
        false
      } catch {
        _ => true
      },
    )
  }
}
