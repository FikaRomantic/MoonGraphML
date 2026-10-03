///|
test "model equivalence ignores XML spelling but not actual attribute changes" {
  let a = try! parse(
    "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><key id=\"k\" attr.type=\"double\"><default>NaN</default></key><graph edgedefault=\"directed\"><node id=\"a\"><data key=\"k\">1.0</data></node><edge source=\"a\" target=\"a\"/></graph></graphml>",
  )
  let b = try! parse(
    "<g:graphml xmlns:g=\"http://graphml.graphdrawing.org/xmlns\"><g:key attr.type=\"double\" id=\"k\"><g:default>NaN</g:default></g:key><g:graph edgedefault=\"directed\"><g:node id=\"a\"><g:data key=\"k\">1e0</g:data></g:node><g:edge target=\"a\" directed=\"true\" source=\"a\"/></g:graph></g:graphml>",
  )
  assert_true(a.equivalent(b))
  assert_true(a.equivalent(try! parse(serialize(a))))
  let edge = { ..b.graphs()[0].edges[0], directed: Some(false), }
  let changed = try! b.replace_edge(
    { graph: GraphAddress::root(0), index: 0, },
    edge,
  )
  assert_false(a.equivalent(changed))
}

///|
test "XML payload adjacent text and attribute order are compared semantically" {
  let a = try! parse(
    "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><key id=\"k\"/><data key=\"k\"><x xmlns=\"urn:x\" a=\"1\" b=\"2\">a<![CDATA[b]]>c</x></data></graphml>",
  )
  let b = try! parse(
    "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><key id=\"k\"/><data key=\"k\"><p:x xmlns:p=\"urn:x\" b=\"2\" a=\"1\">abc</p:x></data></graphml>",
  )
  assert_true(a.equivalent(b))
}
