///|
test "reference lexical tolerance is explicit and type-scoped" {
  let input = "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><key id=\"b\" attr.type=\"boolean\"><default>False</default></key><key id=\"f\" attr.type=\"double\"/><key id=\"s\" attr.type=\"string\"/><data key=\"b\">True</data><data key=\"f\">inf</data><data key=\"s\">True</data></graphml>"
  assert_true(
    try {
      let _ = parse(input)
      false
    } catch {
      _ => true
    },
  )
  let doc = try! parse(input, profile=ReferenceLibraries)
  assert_true(doc.data()[0].value is ScalarValue(BooleanValue(true)))
  assert_true(doc.data()[2].value is ScalarValue(TextValue("True")))
  assert_true(doc.equivalent(try! parse(serialize(doc))))
}
