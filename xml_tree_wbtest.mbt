///|
test "namespace-aware tree does not confuse attribute and element namespaces" {
  let tree = try! read_tree(
    "<g:graphml xmlns:g='http://graphml.graphdrawing.org/xmlns'><g:graph id='G' edgedefault='directed'/></g:graphml>",
    Limits::default(),
  )
  assert_eq(tree.name, "graphml")
  assert_eq(tree.namespace_uri, Some("http://graphml.graphdrawing.org/xmlns"))
  let children = try! element_children(tree)
  assert_eq(try! required_attribute(children[0], "id"), "G")
}

///|
test "external entity declaration is rejected before dependency parsing" {
  let input = "<!DOCTYPE graphml [<!ENTITY external SYSTEM 'file:///secret'>]><graphml>&external;</graphml>"
  assert_true(
    try {
      let _ = read_tree(input, Limits::default())
      false
    } catch {
      Unsupported(..) => true
      _ => false
    },
  )
  let tree = try! read_tree(
    "<x><![CDATA[<!DOCTYPE example>]]></x>",
    Limits::default(),
  )
  assert_eq(try! element_text(tree), "<!DOCTYPE example>")
}

///|
test "tree budgets cover input, events and nesting" {
  let limits = Limits::default()
  for
    bounds in [
      { ..limits, input_bytes: 3, },
      { ..limits, xml_depth: 1, },
      { ..limits, xml_elements: 1, },
    ] {
    assert_true(
      try {
        let _ = read_tree("<x><y/></x>", bounds)
        false
      } catch {
        LimitExceeded(..) => true
        _ => false
      },
    )
  }
}
