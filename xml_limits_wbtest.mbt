///|
test "fragmented text cannot bypass per-element text budget" {
  assert_true(
    try {
      let _ = read_tree("<a>123<![CDATA[456]]>7</a>", {
        ..Limits::default(),
        text_bytes: 6,
      })
      false
    } catch {
      LimitExceeded(resource="text_bytes", ..) => true
      _ => false
    },
  )
  let tree = try! read_tree("<a>123<b>456</b>7</a>", {
    ..Limits::default(),
    text_bytes: 4,
  })
  assert_eq(tree.content.length(), 3)
}

///|
test "namespace declarations consume attribute and text budgets" {
  assert_true(
    try {
      let _ = read_tree("<a xmlns:p=\"urn:p\" xmlns:q=\"urn:q\"/>", {
        ..Limits::default(),
        attributes_per_element: 1,
      })
      false
    } catch {
      LimitExceeded(..) => true
      _ => false
    },
  )
  assert_true(
    try {
      let _ = read_tree("<a xmlns:p=\"urn:long\"/>", {
        ..Limits::default(),
        text_bytes: 4,
      })
      false
    } catch {
      LimitExceeded(..) => true
      _ => false
    },
  )
}
