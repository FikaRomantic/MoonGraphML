///|
fn main raise {
  let graph = @graphml.Graph::new(@graphml.Undirected, id="network")
  let switch = @graphml.Node::new("switch")
  switch.ports.push(@graphml.Port::new("eth0"))
  let server = @graphml.Node::new("server")
  server.ports.push(@graphml.Port::new("eth0"))
  graph.nodes.append([switch, server])
  graph.edges.push(
    @graphml.Edge::new(
      "switch",
      "server",
      source_port="eth0",
      target_port="eth0",
    ),
  )
  let vlan = @graphml.Hyperedge::new(id="vlan")
  vlan.endpoints.append([
    @graphml.Endpoint::new("switch", port="eth0"),
    @graphml.Endpoint::new("server", port="eth0"),
  ])
  graph.hyperedges.push(vlan)
  let document = try! @graphml.Document::new([], [graph])
  let renamed = try! document.rename_port(0, "server", "eth0", "lan0")
  assert_eq(renamed.graphs()[0].hyperedges[0].endpoints[1].port, Some("lan0"))
  println(try! @graphml.serialize(renamed))
}
