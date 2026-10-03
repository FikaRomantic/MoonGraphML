///|
fn port_exists(ports : Array[Port], name : String) -> Bool {
  ports.any(fn(port) { port.name == name || port_exists(port.ports, name) })
}

///|
fn rename_ports(
  ports : Array[Port],
  old_name : String,
  new_name : String,
) -> Array[Port] {
  ports.map(fn(port) {
    {
      ..port,
      name: if port.name == old_name {
        new_name
      } else {
        port.name
      },
      ports: rename_ports(port.ports, old_name, new_name),
    }
  })
}

///|
fn renamed_port_reference(
  node : String,
  port : String?,
  target : String,
  old_name : String,
  new_name : String,
) -> String? {
  if node == target && port == Some(old_name) {
    Some(new_name)
  } else {
    port
  }
}

///|
fn rename_port_graph(
  graph : Graph,
  target : String,
  old_name : String,
  new_name : String,
) -> Graph {
  {
    ..graph,
    nodes: graph.nodes.map(fn(node) {
      {
        ..node,
        ports: if node.id == target {
          rename_ports(node.ports, old_name, new_name)
        } else {
          node.ports
        },
        graph: node.graph.map(fn(nested) {
          rename_port_graph(nested, target, old_name, new_name)
        }),
      }
    }),
    edges: graph.edges.map(fn(edge) {
      {
        ..edge,
        source_port: renamed_port_reference(
          edge.source,
          edge.source_port,
          target,
          old_name,
          new_name,
        ),
        target_port: renamed_port_reference(
          edge.target,
          edge.target_port,
          target,
          old_name,
          new_name,
        ),
        graph: edge.graph.map(fn(nested) {
          rename_port_graph(nested, target, old_name, new_name)
        }),
      }
    }),
    hyperedges: graph.hyperedges.map(fn(hyperedge) {
      {
        ..hyperedge,
        endpoints: hyperedge.endpoints.map(fn(endpoint) {
          {
            ..endpoint,
            port: renamed_port_reference(
              endpoint.node,
              endpoint.port,
              target,
              old_name,
              new_name,
            ),
          }
        }),
        graph: hyperedge.graph.map(fn(nested) {
          rename_port_graph(nested, target, old_name, new_name)
        }),
      }
    }),
  }
}

///|
/// Rename a hierarchical port and update binary edges and hyperedge endpoints atomically.
pub fn Document::rename_port(
  self : Document,
  root : Int,
  node_id : String,
  old_name : String,
  new_name : String,
  limits? : Limits = Limits::default(),
) -> Document raise GraphError {
  bounded_index(root, self.graphs.length(), "rename.root")
  valid_token(new_name, "port.name")
  let node = GraphIndex::new(self)
    .node(root, node_id)
    .unwrap_or_else(() => {
      raise InvalidGraph(path="rename.node", reason="node does not exist")
    })
  require(
    port_exists(node.ports, old_name),
    "port.name",
    "port to rename does not exist",
  )
  require(
    old_name == new_name || !port_exists(node.ports, new_name),
    "port.name",
    "new port name already exists",
  )
  self.replace_graph(
    GraphAddress::root(root),
    rename_port_graph(self.graphs[root], node_id, old_name, new_name),
    limits~,
  )
}
