///|
test "typed values preserve string whitespace and exact int64" {
  assert_true(
    try! Scalar::parse(StringValue, "  blue  ").equivalent(
      TextValue("  blue  "),
    ),
  )
  assert_true(
    try! Scalar::parse(Int64, "9223372036854775807").equivalent(
      LongValue(9223372036854775807L),
    ),
  )
  assert_true(
    try! Scalar::parse(Int32, "-2147483648").equivalent(
      IntegerValue(-2147483648),
    ),
  )
  assert_eq(try! Scalar::parse(Boolean, " 1 ").lexical(), "true")
}

///|
test "typed values reject overflow and invalid lexical forms" {
  for
    (kind, text) in [
      (Int32, "2147483648"),
      (Int64, "9223372036854775808"),
      (Int32, "0xff"),
      (Boolean, "yes"),
      (Float64, "1e"),
      (Float64, "nan"),
      (Float32, "1e40"),
    ] {
    assert_true(
      try {
        let _ = Scalar::parse(kind, text)
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "nonfinite GraphML lexical values and scalar roundtrips" {
  for kind in [Float32, Float64] {
    for text in ["INF", "-INF", "NaN", "-.5e2", "0.0", "-0.0"] {
      let value = try! Scalar::parse(kind, text)
      assert_true(value.equivalent(try! Scalar::parse(kind, value.lexical())))
    }
  }
}
