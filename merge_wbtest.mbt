///|
test "document merge prefixes global declarations but retains independent node scopes" {
  let doc = try! parse(
    "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><key id=\"k\" attr.type=\"int\"/><data key=\"k\">4</data><graph id=\"g\" edgedefault=\"directed\"><node id=\"a\"><data key=\"k\">5</data><graph id=\"nested\" edgedefault=\"undirected\"/></node></graph></graphml>",
  )
  let result = try! doc.merge(doc, "import_")
  assert_eq(result.imported_roots, [1])
  assert_eq(result.key_mapping.get("k"), Some("import_k"))
  assert_eq(result.graph_mapping.get("nested"), Some("import_nested"))
  assert_eq(result.document.graphs()[1].nodes[0].id, "a")
  assert_eq(result.document.graphs()[1].nodes[0].data[0].key, "import_k")
  assert_eq(result.document.data()[1].key, "import_k")
  assert_eq(doc.graph_count(), 1)
}

///|
test "merge rejects metadata conflicts and key collisions" {
  let left = try! Document::new(
    [Key::new("import_k", All, StringValue)],
    [],
    description="left",
  )
  let right = try! Document::new(
    [Key::new("k", All, StringValue)],
    [],
    description="right",
  )
  assert_true(
    try {
      let _ = left.merge(right, "import_")
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = left.merge(right, "safe_")
      false
    } catch {
      _ => true
    },
  )
  let a = try! Document::new([], [], extra=[
    { namespace_uri: Some("urn:a"), name: "mode", value: "a", },
  ])
  let b = try! Document::new([], [], extra=[
    { namespace_uri: Some("urn:a"), name: "mode", value: "b", },
  ])
  assert_true(
    try {
      let _ = a.merge(b, "import_")
      false
    } catch {
      _ => true
    },
  )
}
