///|
test "rename key rewrites nested graph and port attributes without mutating source" {
  let doc = try! parse(
    "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><key id=\"k\" attr.type=\"int\"/><data key=\"k\">1</data><graph edgedefault=\"directed\"><node id=\"a\"><port name=\"p\"><data key=\"k\">2</data></port><graph edgedefault=\"directed\"><data key=\"k\">3</data></graph></node></graph></graphml>",
  )
  let renamed = try! doc.rename_key("k", "number")
  assert_eq(renamed.data()[0].key, "number")
  assert_eq(renamed.graphs()[0].nodes[0].ports[0].data[0].key, "number")
  assert_eq(renamed.graphs()[0].nodes[0].graph.unwrap().data[0].key, "number")
  assert_eq(doc.keys()[0].id, "k")
  assert_true(
    try {
      let _ = renamed.remove_key("number")
      false
    } catch {
      _ => true
    },
  )
  let wrong = try! Key::new("number", All, Boolean)
  assert_true(
    try {
      let _ = renamed.replace_key(wrong)
      false
    } catch {
      _ => true
    },
  )
}

///|
test "unused declaration removal and missing rename are explicit" {
  let doc = try! Document::new(
    [Key::new("a", All, StringValue), Key::new("b", All, StringValue)],
    [],
  )
  assert_eq(try! doc.remove_key("a").key_count(), 1)
  assert_true(
    try {
      let _ = doc.rename_key("missing", "c")
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = doc.rename_key("a", "b")
      false
    } catch {
      _ => true
    },
  )
}
