///|
fn rename_node_graph(graph : Graph, old_id : String, new_id : String) -> Graph {
  {
    ..graph,
    nodes: graph.nodes.map(fn(node) {
      {
        ..node,
        id: if node.id == old_id {
          new_id
        } else {
          node.id
        },
        graph: node.graph.map(fn(nested) {
          rename_node_graph(nested, old_id, new_id)
        }),
      }
    }),
    edges: graph.edges.map(fn(edge) {
      {
        ..edge,
        source: if edge.source == old_id {
          new_id
        } else {
          edge.source
        },
        target: if edge.target == old_id {
          new_id
        } else {
          edge.target
        },
        graph: edge.graph.map(fn(nested) {
          rename_node_graph(nested, old_id, new_id)
        }),
      }
    }),
    hyperedges: graph.hyperedges.map(fn(hyperedge) {
      {
        ..hyperedge,
        endpoints: hyperedge.endpoints.map(fn(endpoint) {
          {
            ..endpoint,
            node: if endpoint.node == old_id {
              new_id
            } else {
              endpoint.node
            },
          }
        }),
        graph: hyperedge.graph.map(fn(nested) {
          rename_node_graph(nested, old_id, new_id)
        }),
      }
    }),
  }
}

///|
/// Rename one node in a top-level ID scope and update all edge/hyperedge references.
pub fn Document::rename_node(
  self : Document,
  root : Int32,
  old_id : String,
  new_id : String,
  limits~ : Limits = Limits::default(),
) -> Document raise GraphError {
  bounded_index(root, self.graphs.length(), "rename.root")
  valid_token(new_id, "node.id")
  let index = GraphIndex::new(self)
  require(
    index.node_address(root, old_id) is Some(_),
    "node.id",
    "node to rename does not exist",
  )
  require(
    old_id == new_id || index.node_address(root, new_id) is None,
    "node.id",
    "new node identifier already exists",
  )
  self.replace_graph(
    GraphAddress::root(root),
    rename_node_graph(self.graphs[root], old_id, new_id),
    limits~,
  )
}

///|
/// Replace a node without deleting any incident references implicitly.
pub fn Document::replace_node(
  self : Document,
  address : ElementAddress,
  node : Node,
  limits~ : Limits = Limits::default(),
) -> Document raise GraphError {
  let graph = graph_at(self, address.graph)
  bounded_index(address.index, graph.nodes.length(), "replace.node")
  let nodes = graph.nodes.copy()
  nodes[address.index] = node
  self.replace_graph(address.graph, { ..graph, nodes, }, limits~)
}

///|
/// Replace edge properties, preserving hierarchy and enforcing reference validity.
pub fn Document::replace_edge(
  self : Document,
  address : ElementAddress,
  edge : Edge,
  limits~ : Limits = Limits::default(),
) -> Document raise GraphError {
  let graph = graph_at(self, address.graph)
  bounded_index(address.index, graph.edges.length(), "replace.edge")
  let edges = graph.edges.copy()
  edges[address.index] = edge
  self.replace_graph(address.graph, { ..graph, edges, }, limits~)
}
