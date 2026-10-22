///|
/// Original deterministic corpus generator for cross-language interoperability testing.
fn generate(seed : Int32) -> String raise @gml.GraphError {
  if seed < 0 || seed > 1000000 {
    raise @gml.InvalidGraph(
      path="generate.seed",
      reason="seed must be between 0 and 1000000",
    )
  }
  let keys = [
    @gml.Key::new("label", @gml.NodeScope, @gml.StringValue, name="label"),
    @gml.Key::new("active", @gml.NodeScope, @gml.Boolean, name="active"),
    @gml.Key::new(
      "count",
      @gml.NodeScope,
      @gml.Int32,
      name="count",
      default_value=@gml.IntegerValue(7),
    ),
    @gml.Key::new("large", @gml.NodeScope, @gml.Int64, name="large"),
    @gml.Key::new("score", @gml.NodeScope, @gml.Float32, name="score"),
    @gml.Key::new(
      "weight",
      @gml.EdgeScope,
      @gml.Float64,
      name="weight",
      default_value=@gml.DoubleValue(1.5),
    ),
  ]
  let direction = if seed % 2 == 0 { @gml.Directed } else { @gml.Undirected }
  let builder = @gml.FlatBuilder::new(keys, direction, graph_id="G\{seed}")
  let nodes = 1 + seed % 9
  for i = 0; i < nodes; i = i + 1 {
    let attributes = [
      ("label", @gml.TextValue("节点 \{i} <&> 😀\n\t")),
      ("active", @gml.BooleanValue((seed + i) % 2 == 0)),
      ("large", @gml.LongValue(9007199254740993L + seed.to_int64())),
      ("score", @gml.FloatValue(Float::from_double(i.to_double() / 4.0))),
    ]
    if i % 2 == 0 {
      attributes.push(("count", @gml.IntegerValue(seed + i)))
    }
    builder.add_node("n\{i}", attributes~)
  }
  for i = 0; i < seed % 13; i = i + 1 {
    let source = if i < 3 { 0 } else { (seed + i * 3) % nodes }
    let target = if i == 0 {
      source
    } else if i < 3 {
      nodes - 1
    } else {
      (seed + i * 7) % nodes
    }
    let attributes = if i % 2 == 0 {
      [("weight", @gml.DoubleValue((seed + i).to_double() / 2.0))]
    } else {
      []
    }
    builder.add_edge("n\{source}", "n\{target}", id="e\{i}", attributes~)
  }
  @gml.serialize(builder.finish())
}
