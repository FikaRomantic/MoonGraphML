///|
test "extension payload retains inherited prefix bindings used by QName attributes" {
  let input = "<graphml xmlns='http://graphml.graphdrawing.org/xmlns' xmlns:p='urn:shapes'><key id='k'/><graph edgedefault='directed'><node id='n'><data key='k'><p:shape xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance' xsi:type='p:Rectangle'/></data></node></graph></graphml>"
  let doc = try! parse(input)
  let output = try! serialize(doc)
  assert_true(output.contains("xmlns:p=\"urn:shapes\""))
  assert_true(output.contains("xsi:type=\"p:Rectangle\""))
  assert_true(doc.equivalent(try! parse(output)))
  guard doc.graphs()[0].nodes[0].data[0].value is XmlPayload(values) else {
    abort("missing XML")
  }
  guard values[0] is Element(element) else { abort("missing element") }
  assert_eq(element.prefix, Some("p"))
  element.namespaces.clear()
  assert_true(try! serialize(doc).contains("xmlns:p=\"urn:shapes\""))
}

///|
test "prefixed elements preserve empty default namespace for unprefixed xsi type" {
  let doc = try! parse(
    "<g:graphml xmlns:g='http://graphml.graphdrawing.org/xmlns' xmlns:p='urn:shapes' xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance'><g:key id='k'/><g:data key='k'><p:shape xsi:type='Rectangle'/></g:data></g:graphml>",
  )
  let output = try! serialize(doc)
  let root = try! read_tree(output, Limits::default())
  guard (try! element_children(root))[1].content[0] is Element(shape) else {
    abort("missing shape")
  }
  assert_eq(namespace_uri_for(shape.namespaces, None), Some(""))
  assert_true(doc.equivalent(try! parse(output)))
}

///|
test "XML namespace elements use the implicit xml prefix rather than a forbidden default" {
  let doc = try! parse(
    "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><key id='k'/><data key='k'><xml:note/></data></graphml>",
  )
  let output = try! serialize(doc)
  assert_true(output.contains("<xml:note"))
  assert_false(
    output.contains("xmlns=\"http://www.w3.org/XML/1998/namespace\""),
  )
  assert_true(doc.equivalent(try! parse(output)))
}

///|
test "generated attribute prefixes never override a saved QName binding" {
  let key = (try! inspect_keys(
      "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><key id='k'/></graphml>",
    ))[0]
  let element : XmlElementValue = {
    namespace_uri: Some("urn:shape"),
    name: "shape",
    prefix: Some("p"),
    namespaces: [
      { prefix: Some("p"), namespace_uri: "urn:shape", },
      { prefix: Some("a0"), namespace_uri: "urn:old", },
    ],
    attributes: [
      { namespace_uri: Some("urn:new"), name: "type", value: "a0:Value", },
    ],
    content: [],
  }
  let datum : Datum = {
    key: "k",
    id: None,
    value: XmlPayload([Element(element)]),
    extra: [],
    namespaces: [],
  }
  let doc = try! Document::new([key], [], data=[datum])
  let output = try! serialize(doc)
  assert_true(output.contains("xmlns:a0=\"urn:old\""))
  assert_true(output.contains("xmlns:a1=\"urn:new\""))
  assert_true(doc.equivalent(try! parse(output)))
}

///|
test "QName binding changes are not reported as model-equivalent" {
  let before = "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><key id='k'/><data key='k'><v xmlns='urn:v' xmlns:p='urn:before' type='p:Rectangle'/></data></graphml>"
  let after = "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><key id='k'/><data key='k'><v xmlns='urn:v' xmlns:p='urn:after' type='p:Rectangle'/></data></graphml>"
  assert_false((try! parse(before)).equivalent(try! parse(after)))
  let a = try! parse(
    "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><key id='k'/><data key='k'><p:v xmlns:p='urn:v' xmlns='urn:a' xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance' xsi:type='Rectangle'/></data></graphml>",
  )
  let b = try! parse(
    "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><key id='k'/><data key='k'><p:v xmlns:p='urn:v' xmlns='urn:b' xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance' xsi:type='Rectangle'/></data></graphml>",
  )
  assert_false(a.equivalent(b))
}

///|
test "default extension attributes and QName context survive detached construction" {
  let doc = try! parse(
    "<g:graphml xmlns:g='http://graphml.graphdrawing.org/xmlns' xmlns:p='urn:types'><g:key id='k'><g:default xmlns:m='urn:metadata' m:kind='p:Rectangle'>p:Rectangle</g:default></g:key></g:graphml>",
  )
  assert_eq(doc.keys()[0].default_extra.length(), 1)
  let rebuilt = try! Document::new(doc.keys(), [])
  let output = try! serialize(rebuilt)
  assert_true(output.contains("m:kind=\"p:Rectangle\""))
  assert_true(output.contains("<g:default"))
  assert_true(doc.equivalent(try! parse(output)))
  let modified = doc.keys()
  modified[0].default_extra.clear()
  modified[0].default_namespaces.clear()
  assert_eq(doc.keys()[0].default_extra.length(), 1)
  assert_true(doc.equivalent(rebuilt))
}

///|
test "namespace NCNames and description attribute rejection apply at read time" {
  assert_true(
    try {
      let _ = parse(
        "<?bad:target instruction?><graphml xmlns='http://graphml.graphdrawing.org/xmlns'/>",
      )
      false
    } catch {
      _ => true
    },
  )
  for
    payload in [
      "<p:1shape xmlns:p='urn:p'/>", "<p:shape xmlns:p='urn:p' xmlns:1bad='urn:bad'/>",
      "<p:shape xmlns:p='urn:p' p:1attr='x'/>",
    ] {
    let input = "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><key id='k'/><data key='k'>\{payload}</data></graphml>"
    assert_true(
      try {
        let _ = parse(input)
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      let _ = parse(
        "<graphml xmlns='http://graphml.graphdrawing.org/xmlns'><desc xml:lang='en'>description</desc></graphml>",
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = parse(
        "<graphml xmlns='http://graphml.graphdrawing.org/xmlns' xmlns:a='urn:x' xmlns:b='urn:x' a:v='1' b:v='2'/>",
      )
      false
    } catch {
      InvalidXml(_) => true
      _ => false
    },
  )
}
