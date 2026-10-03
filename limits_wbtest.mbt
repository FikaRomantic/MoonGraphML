///|
test "limits reject negative allowances" {
  let bounds = Limits::default()
  bounds.validate() catch {
    _ => abort("default limits invalid")
  }
  let bad = { ..bounds, nodes: -1, }
  let rejected = try {
    bad.validate()
    false
  } catch {
    InvalidGraph(..) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "depth hard cap and zero limits are explicit" {
  let bounds = Limits::default()
  assert_true(
    try {
      { ..bounds, xml_depth: 257, }.validate()
      false
    } catch {
      _ => true
    },
  )
  try! { ..bounds, nodes: 0, }.validate()
}
