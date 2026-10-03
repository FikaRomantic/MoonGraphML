///|
/// Counts describe stored structure, not inferred expansion of hyperedges or locators.
pub(all) struct Statistics {
  keys : Int
  graphs : Int
  nodes : Int
  edges : Int
  hyperedges : Int
  endpoints : Int
  ports : Int
  data_entries : Int
  max_graph_depth : Int
  has_mixed_direction : Bool
  has_parallel_edges : Bool
  has_self_loops : Bool
  has_locators : Bool
  has_xml_payloads : Bool
} derive(Eq, @debug.Debug)

///|
pub extend Statistics with Eq::{equal, not_equal}

///|
pub extend Statistics with @debug.Debug::{to_repr}

///|
priv struct StatsBuilder {
  mut value : Statistics
}

///|
fn count_data(builder : StatsBuilder, data : Array[Datum]) -> Unit {
  builder.value = {
    ..builder.value,
    data_entries: builder.value.data_entries + data.length(),
    has_xml_payloads: builder.value.has_xml_payloads ||
    data.any(fn(datum) { datum.value is XmlPayload(_) }),
  }
}

///|
fn count_port(builder : StatsBuilder, port : Port) -> Unit {
  builder.value = { ..builder.value, ports: builder.value.ports + 1, }
  count_data(builder, port.data)
  for nested in port.ports {
    count_port(builder, nested)
  }
}

///|
fn count_graph(builder : StatsBuilder, graph : Graph, depth : Int) -> Unit {
  builder.value = {
    ..builder.value,
    graphs: builder.value.graphs + 1,
    nodes: builder.value.nodes + graph.nodes.length(),
    edges: builder.value.edges + graph.edges.length(),
    hyperedges: builder.value.hyperedges + graph.hyperedges.length(),
    max_graph_depth: if depth > builder.value.max_graph_depth {
      depth
    } else {
      builder.value.max_graph_depth
    },
    has_locators: builder.value.has_locators || graph.locator is Some(_),
  }
  count_data(builder, graph.data)
  for node in graph.nodes {
    count_data(builder, node.data)
    builder.value = {
      ..builder.value,
      has_locators: builder.value.has_locators || node.locator is Some(_),
    }
    for port in node.ports {
      count_port(builder, port)
    }
    if node.graph is Some(nested) {
      count_graph(builder, nested, depth + 1)
    }
  }
  let mut has_directed = false
  let mut has_undirected = false
  let pairs : Map[(String, String, Bool), Bool] = Map([])
  for edge in graph.edges {
    let directed = edge.effective_direction(graph) == Directed
    has_directed = has_directed || directed
    has_undirected = has_undirected || !directed
    let pair = if !directed && edge.target < edge.source {
      (edge.target, edge.source, directed)
    } else {
      (edge.source, edge.target, directed)
    }
    builder.value = {
      ..builder.value,
      has_parallel_edges: builder.value.has_parallel_edges ||
      pairs.contains(pair),
      has_self_loops: builder.value.has_self_loops || edge.source == edge.target,
    }
    pairs[pair] = true
    count_data(builder, edge.data)
    if edge.graph is Some(nested) {
      count_graph(builder, nested, depth + 1)
    }
  }
  builder.value = {
    ..builder.value,
    has_mixed_direction: builder.value.has_mixed_direction ||
    (has_directed && has_undirected),
  }
  for hyperedge in graph.hyperedges {
    count_data(builder, hyperedge.data)
    builder.value = {
      ..builder.value,
      endpoints: builder.value.endpoints + hyperedge.endpoints.length(),
    }
    if hyperedge.graph is Some(nested) {
      count_graph(builder, nested, depth + 1)
    }
  }
}

///|
/// Linear scan of structure plus one edge-pair map per graph, without layout or graph algorithms.
pub fn Document::statistics(self : Document) -> Statistics {
  let builder : StatsBuilder = {
    value: {
      keys: self.keys.length(),
      graphs: 0,
      nodes: 0,
      edges: 0,
      hyperedges: 0,
      endpoints: 0,
      ports: 0,
      data_entries: 0,
      max_graph_depth: 0,
      has_mixed_direction: false,
      has_parallel_edges: false,
      has_self_loops: false,
      has_locators: false,
      has_xml_payloads: self.keys.any(fn(key) {
        key.default_value is Some(XmlPayload(_))
      }),
    },
  }
  count_data(builder, self.data)
  for graph in self.graphs {
    count_graph(builder, graph, 1)
  }
  builder.value
}
