///|
/// Each step names the owning element of a nested graph, by its ordinal in that graph.
pub(all) enum GraphStep {
  NodeGraph(Int)
  EdgeGraph(Int)
  HyperedgeGraph(Int)
} derive(Eq, @debug.Debug)

///|
pub extend GraphStep with Eq::{equal, not_equal}

///|
pub extend GraphStep with @debug.Debug::{to_repr}

///|
pub(all) struct GraphAddress {
  root : Int
  steps : Array[GraphStep]
} derive(Eq, @debug.Debug)

///|
pub extend GraphAddress with Eq::{equal, not_equal}

///|
pub extend GraphAddress with @debug.Debug::{to_repr}

///|
pub fn GraphAddress::root(index : Int) -> GraphAddress {
  { root: index, steps: [], }
}

///|
pub fn GraphAddress::child(
  self : GraphAddress,
  step : GraphStep,
) -> GraphAddress {
  let steps = self.steps.copy()
  steps.push(step)
  { root: self.root, steps, }
}

///|
fn copy_address(address : GraphAddress) -> GraphAddress {
  { ..address, steps: address.steps.copy(), }
}

///|
fn bounded_index(
  index : Int,
  size : Int,
  path : String,
) -> Unit raise GraphError {
  require(index >= 0 && index < size, path, "index out of range")
}

///|
fn graph_at(doc : Document, address : GraphAddress) -> Graph raise GraphError {
  bounded_index(address.root, doc.graphs.length(), "graph.root")
  let mut graph = doc.graphs[address.root]
  for step in address.steps {
    let nested = match step {
      NodeGraph(index) => {
        bounded_index(index, graph.nodes.length(), "graph.node")
        graph.nodes[index].graph
      }
      EdgeGraph(index) => {
        bounded_index(index, graph.edges.length(), "graph.edge")
        graph.edges[index].graph
      }
      HyperedgeGraph(index) => {
        bounded_index(index, graph.hyperedges.length(), "graph.hyperedge")
        graph.hyperedges[index].graph
      }
    }
    graph = match nested {
      Some(value) => value
      None =>
        raise InvalidGraph(
          path="graph.address",
          reason="owning element has no nested graph",
        )
    }
  }
  graph
}

///|
/// Get a detached graph using a structural address, including graphs without IDs.
pub fn Document::graph_at(
  self : Document,
  address : GraphAddress,
) -> Graph raise GraphError {
  clone_graph(graph_at(self, address))
}
