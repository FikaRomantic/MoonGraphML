///|
pub(all) struct ElementAddress {
  graph : GraphAddress
  index : Int32
} derive(Eq, @debug.Debug)

///|
pub extend ElementAddress with Eq::{equal, not_equal}

///|
pub extend ElementAddress with @debug.Debug::{to_repr}

///|
fn copy_element_address(address : ElementAddress) -> ElementAddress {
  { ..address, graph: copy_address(address.graph), }
}

///|
/// IDs for nodes/edges are scoped to the top-level graph; graph IDs are document-global.
pub struct GraphIndex {
  priv document : Document
  priv graphs : Map[String, GraphAddress]
  priv nodes : Map[(Int32, String), ElementAddress]
  priv edges : Map[(Int32, String), ElementAddress]
  priv hyperedges : Map[(Int32, String), ElementAddress]
  priv incident : Map[(Int32, String), Array[ElementAddress]]
  priv endpoints : Map[(Int32, String), Array[ElementAddress]]
}

///|
pub fn GraphIndex::new(doc : Document) -> GraphIndex {
  let index : GraphIndex = {
    document: doc,
    graphs: Map([]),
    nodes: Map([]),
    edges: Map([]),
    hyperedges: Map([]),
    incident: Map([]),
    endpoints: Map([]),
  }
  for root = 0; root < doc.graphs.length(); root = root + 1 {
    index_graph(index, doc.graphs[root], GraphAddress::root(root))
  }
  index
}

///|
fn add_incident(
  map : Map[(Int32, String), Array[ElementAddress]],
  key : (Int32, String),
  address : ElementAddress,
) -> Unit {
  match map.get(key) {
    Some(values) => values.push(address)
    None => map[key] = [address]
  }
}

///|
fn index_graph(
  index : GraphIndex,
  graph : Graph,
  address : GraphAddress,
) -> Unit {
  if graph.id is Some(id) {
    index.graphs[id] = address
  }
  for ordinal = 0; ordinal < graph.nodes.length(); ordinal = ordinal + 1 {
    let node = graph.nodes[ordinal]
    index.nodes[(address.root, node.id)] = { graph: address, index: ordinal, }
    if node.graph is Some(nested) {
      index_graph(index, nested, address.child(NodeGraph(ordinal)))
    }
  }
  for ordinal = 0; ordinal < graph.edges.length(); ordinal = ordinal + 1 {
    let edge = graph.edges[ordinal]
    let location = { graph: address, index: ordinal, }
    if edge.id is Some(id) {
      index.edges[(address.root, id)] = location
    }
    add_incident(index.incident, (address.root, edge.source), location)
    // Incident lists contain a loop once; degree counting is a separate graph algorithm.
    if edge.target != edge.source {
      add_incident(index.incident, (address.root, edge.target), location)
    }
    if edge.graph is Some(nested) {
      index_graph(index, nested, address.child(EdgeGraph(ordinal)))
    }
  }
  for ordinal = 0; ordinal < graph.hyperedges.length(); ordinal = ordinal + 1 {
    let hyperedge = graph.hyperedges[ordinal]
    let location = { graph: address, index: ordinal, }
    if hyperedge.id is Some(id) {
      index.hyperedges[(address.root, id)] = location
    }
    let seen : Map[String, Bool] = Map([])
    for endpoint in hyperedge.endpoints {
      if !seen.contains(endpoint.node) {
        seen[endpoint.node] = true
        add_incident(index.endpoints, (address.root, endpoint.node), location)
      }
    }
    if hyperedge.graph is Some(nested) {
      index_graph(index, nested, address.child(HyperedgeGraph(ordinal)))
    }
  }
}

///|
pub fn GraphIndex::graph_address(
  self : GraphIndex,
  id : String,
) -> GraphAddress? {
  self.graphs.get(id).map(copy_address)
}

///|
pub fn GraphIndex::node_address(
  self : GraphIndex,
  root : Int32,
  id : String,
) -> ElementAddress? {
  self.nodes.get((root, id)).map(copy_element_address)
}

///|
pub fn GraphIndex::edge_address(
  self : GraphIndex,
  root : Int32,
  id : String,
) -> ElementAddress? {
  self.edges.get((root, id)).map(copy_element_address)
}

///|
pub fn GraphIndex::hyperedge_address(
  self : GraphIndex,
  root : Int32,
  id : String,
) -> ElementAddress? {
  self.hyperedges.get((root, id)).map(copy_element_address)
}

///|
pub fn GraphIndex::node(self : GraphIndex, root : Int32, id : String) -> Node? {
  self.nodes
  .get((root, id))
  .map(fn(address) {
    clone_node(
      (try! graph_at(self.document, address.graph)).nodes[address.index],
    )
  })
}

///|
pub fn GraphIndex::edge(self : GraphIndex, root : Int32, id : String) -> Edge? {
  self.edges
  .get((root, id))
  .map(fn(address) {
    clone_edge(
      (try! graph_at(self.document, address.graph)).edges[address.index],
    )
  })
}

///|
pub fn GraphIndex::incident_edges(
  self : GraphIndex,
  root : Int32,
  node : String,
) -> Array[ElementAddress] {
  self.incident.get((root, node)).unwrap_or([]).map(copy_element_address)
}

///|
pub fn GraphIndex::incident_hyperedges(
  self : GraphIndex,
  root : Int32,
  node : String,
) -> Array[ElementAddress] {
  self.endpoints.get((root, node)).unwrap_or([]).map(copy_element_address)
}

///|
pub fn Document::edge_at(
  self : Document,
  address : ElementAddress,
) -> Edge raise GraphError {
  let graph = graph_at(self, address.graph)
  bounded_index(address.index, graph.edges.length(), "edge.index")
  clone_edge(graph.edges[address.index])
}

///|
pub fn Document::node_at(
  self : Document,
  address : ElementAddress,
) -> Node raise GraphError {
  let graph = graph_at(self, address.graph)
  bounded_index(address.index, graph.nodes.length(), "node.index")
  clone_node(graph.nodes[address.index])
}
