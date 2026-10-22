///|
/// Directed arcs follow either source-to-target or target-to-source. Undirected
/// edges always contribute both orientations, except a self-loop contributes one.
pub(all) enum CsrOrientation {
  Outgoing
  Incoming
} derive(Eq, @debug.Debug)

///|
pub extend CsrOrientation with Eq::{equal, not_equal}

///|
pub extend CsrOrientation with @debug.Debug::{to_repr}

///|
/// One stored adjacency entry. edge_index refers to the original FlatGraph edge
/// order. reversed marks an arc emitted opposite to stored endpoint order;
/// incoming directed self-loops are marked reversed even though endpoints agree.
pub(all) struct CsrEntry {
  target : Int32
  edge_index : Int32
  reversed : Bool
} derive(Eq, @debug.Debug)

///|
pub extend CsrEntry with Eq::{equal, not_equal}

///|
pub extend CsrEntry with @debug.Debug::{to_repr}

///|
/// Owned compressed sparse rows, not an aggregated numerical matrix. Parallel
/// entries are retained and rows follow original edge order, not sorted columns.
/// All array accessors return copies; caller mutation cannot corrupt row offsets.
pub struct CsrAdjacency {
  node_ids : Array[String]
  positions : Map[String, Int32]
  indptr : Array[Int32]
  indices : Array[Int32]
  edge_indices : Array[Int32]
  reversed : Array[Bool]
}

///|
pub fn CsrAdjacency::node_count(self : CsrAdjacency) -> Int32 {
  self.node_ids.length()
}

///|
pub fn CsrAdjacency::arc_count(self : CsrAdjacency) -> Int32 {
  self.indices.length()
}

///|
pub fn CsrAdjacency::node_index(self : CsrAdjacency, id : String) -> Int32? {
  self.positions.get(id)
}

///|
pub fn CsrAdjacency::node_ids(self : CsrAdjacency) -> Array[String] {
  self.node_ids.copy()
}

///|
pub fn CsrAdjacency::indptr(self : CsrAdjacency) -> Array[Int32] {
  self.indptr.copy()
}

///|
pub fn CsrAdjacency::indices(self : CsrAdjacency) -> Array[Int32] {
  self.indices.copy()
}

///|
pub fn CsrAdjacency::edge_indices(self : CsrAdjacency) -> Array[Int32] {
  self.edge_indices.copy()
}

///|
pub fn CsrAdjacency::reversed(self : CsrAdjacency) -> Array[Bool] {
  self.reversed.copy()
}

///|
/// Copy one row in O(degree) time without copying all other rows or metadata.
pub fn CsrAdjacency::row(
  self : CsrAdjacency,
  node_index : Int32,
) -> Array[CsrEntry] raise GraphError {
  bounded_index(node_index, self.node_ids.length(), "csr.row")
  let result = []
  for i = self.indptr[node_index]; i < self.indptr[node_index + 1]; i = i + 1 {
    result.push({
      target: self.indices[i],
      edge_index: self.edge_indices[i],
      reversed: self.reversed[i],
    })
  }
  result
}

///|
fn csr_put(
  cursor : Array[Int32],
  indices : Array[Int32],
  edge_indices : Array[Int32],
  reversed : Array[Bool],
  source : Int32,
  target : Int32,
  edge_index : Int32,
  reverse : Bool,
) -> Unit {
  let slot = cursor[source]
  indices[slot] = target
  edge_indices[slot] = edge_index
  reversed[slot] = reverse
  cursor[source] = slot + 1
}

///|
/// Export a topology adapter in O(V+E) expected time and O(V+A) space, A <= 2E.
/// Preflight the configurable arc ceiling before allocating arc buffers. Node
/// ordinals follow source node order, edge ordinals follow source edge order.
/// Weights/XML/IDs stay in the original FlatGraph and can be joined by ordinal;
/// they are neither coerced to Double nor silently aggregated here.
pub fn FlatGraph::to_csr(
  self : FlatGraph,
  orientation~ : CsrOrientation = Outgoing,
  max_arcs~ : Int32 = 2000000,
) -> CsrAdjacency raise GraphError {
  require(max_arcs >= 0, "csr.max_arcs", "negative arc budget")
  let graph = self.graph
  let size = graph.nodes.length()
  check_bound("csr.nodes", size, 2147483646)
  let mut arc_count = 0
  for edge in graph.edges {
    let amount = if edge.effective_direction(graph) == Undirected &&
      edge.source != edge.target {
      2
    } else {
      1
    }
    if amount > max_arcs - arc_count {
      raise LimitExceeded(resource="csr.arcs", limit=max_arcs)
    }
    arc_count = arc_count + amount
  }
  let node_ids = graph.nodes.map(fn(node) { node.id })
  let positions : Map[String, Int32] = Map([])
  for i = 0; i < size; i = i + 1 {
    positions[node_ids[i]] = i
  }
  let counts = Array::make(size, 0)
  for edge in graph.edges {
    let source = positions.get(edge.source).unwrap()
    let target = positions.get(edge.target).unwrap()
    if edge.effective_direction(graph) == Undirected {
      counts[source] = counts[source] + 1
      if source != target {
        counts[target] = counts[target] + 1
      }
    } else {
      let row = if orientation == Outgoing { source } else { target }
      counts[row] = counts[row] + 1
    }
  }
  let indptr = [0]
  for count in counts {
    indptr.push(indptr[indptr.length() - 1] + count)
  }
  let cursor = indptr.copy()
  let indices = Array::make(arc_count, 0)
  let edge_indices = Array::make(arc_count, 0)
  let reversed = Array::make(arc_count, false)
  for i = 0; i < graph.edges.length(); i = i + 1 {
    let edge = graph.edges[i]
    let source = positions.get(edge.source).unwrap()
    let target = positions.get(edge.target).unwrap()
    if edge.effective_direction(graph) == Undirected {
      csr_put(cursor, indices, edge_indices, reversed, source, target, i, false)
      if source != target {
        csr_put(
          cursor, indices, edge_indices, reversed, target, source, i, true,
        )
      }
    } else if orientation == Outgoing {
      csr_put(cursor, indices, edge_indices, reversed, source, target, i, false)
    } else {
      csr_put(cursor, indices, edge_indices, reversed, target, source, i, true)
    }
  }
  { node_ids, positions, indptr, indices, edge_indices, reversed, }
}
