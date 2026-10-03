///|
test "defaults preserve explicit empty values and declaration order" {
  let doc = try! Document::new(
    [
      Key::new(
        "label",
        NodeScope,
        StringValue,
        name="label",
        default_value=TextValue("default"),
      ),
      Key::new("weight", All, Int32, default_value=IntegerValue(3)),
      Key::new("graph", GraphScope, Boolean, default_value=BooleanValue(true)),
    ],
    [],
  )
  let attributes = try! Attributes::new(doc, NodeScope, [
    Datum::new("label", TextValue("")),
  ])
  assert_true(try! (attributes.scalar("label") is Some(TextValue(""))))
  assert_true(try! (attributes.scalar("weight") is Some(IntegerValue(3))))
  assert_true(try! (attributes.scalar("weight", use_default=false) is None))
  assert_eq(try! attributes.key_by_name("label"), Some("label"))
  assert_eq(attributes.resolved().map(fn(datum) { datum.key }), [
    "label", "weight",
  ])
  assert_true(
    try {
      let _ = attributes.get("graph")
      false
    } catch {
      _ => true
    },
  )
}

///|
test "ambiguous names and duplicate explicit values are rejected" {
  let doc = try! Document::new(
    [
      Key::new("a", NodeScope, StringValue, name="same"),
      Key::new("b", All, StringValue, name="same"),
    ],
    [],
  )
  let attrs = try! Attributes::new(doc, NodeScope, [])
  assert_true(
    try {
      let _ = attrs.key_by_name("same")
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = Attributes::new(doc, NodeScope, [
        Datum::new("a", TextValue("1")),
        Datum::new("a", TextValue("2")),
      ])
      false
    } catch {
      _ => true
    },
  )
}
