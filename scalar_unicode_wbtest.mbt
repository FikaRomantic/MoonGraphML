///|
test "standalone scalar parsing rejects unchecked malformed Unicode for every type" {
  for kind in [Boolean, Int32, Int64, Float32, Float64, StringValue] {
    for
      bad in [
        b"\x00\xD8".to_unchecked_string(),
        b"\x00\xDC".to_unchecked_string(),
      ] {
      assert_true(
        try {
          let _ = Scalar::parse(kind, bad)
          false
        } catch {
          InvalidGraph(path="xml.unicode", ..) => true
          _ => false
        },
      )
    }
  }
  assert_true(
    try! (Scalar::parse(StringValue, "  中😀\t  ")
    is TextValue("  中😀\t  ")),
  )
}
