///|
/// The mappings make import renaming explicit to applications.
pub(all) struct MergeResult {
  document : Document
  imported_roots : Array[Int]
  key_mapping : Map[String, String]
  graph_mapping : Map[String, String]
}

///|
fn prefix_graph_ids(
  graph : Graph,
  prefix : String,
  mapping : Map[String, String],
) -> Graph {
  let id = graph.id.map(fn(id) {
    let renamed = prefix + id
    mapping[id] = renamed
    renamed
  })
  {
    ..graph,
    id,
    nodes: graph.nodes.map(fn(node) {
      {
        ..node,
        graph: node.graph.map(fn(child) {
          prefix_graph_ids(child, prefix, mapping)
        }),
      }
    }),
    edges: graph.edges.map(fn(edge) {
      {
        ..edge,
        graph: edge.graph.map(fn(child) {
          prefix_graph_ids(child, prefix, mapping)
        }),
      }
    }),
    hyperedges: graph.hyperedges.map(fn(hyperedge) {
      {
        ..hyperedge,
        graph: hyperedge.graph.map(fn(child) {
          prefix_graph_ids(child, prefix, mapping)
        }),
      }
    }),
  }
}

///|
fn merge_root_attributes(
  left : Array[XmlAttributeValue],
  right : Array[XmlAttributeValue],
) -> Array[XmlAttributeValue] raise GraphError {
  let result = left.copy()
  let known : Map[(String?, String), String] = Map([])
  for attribute in left {
    known[(attribute.namespace_uri, attribute.name)] = attribute.value
  }
  for attribute in right {
    let name = (attribute.namespace_uri, attribute.name)
    match known.get(name) {
      Some(value) =>
        require(
          value == attribute.value,
          "merge.graphml",
          "conflicting document extension attribute",
        )
      None => {
        known[name] = attribute.value
        result.push(attribute)
      }
    }
  }
  result
}

///|
/// Opaque root values may use even an unprefixed application-defined QName.
/// Without their schema, conflicting contexts are rejected when both roots carry values.
fn merge_root_namespaces(
  left : Document,
  right : Document,
) -> Array[NamespaceBinding] raise GraphError {
  let result = left.namespaces.copy()
  for binding in right.namespaces {
    match namespace_uri_for(result, binding.prefix) {
      Some(uri) if uri != binding.namespace_uri => {
        require(
          left.extra.is_empty() || right.extra.is_empty(),
          "merge.graphml",
          "conflicting namespace context for opaque root extension values",
        )
        if left.extra.is_empty() && !right.extra.is_empty() {
          set_namespace_binding(result, binding.prefix, binding.namespace_uri)
        }
      }
      Some(_) => ()
      None =>
        set_namespace_binding(result, binding.prefix, binding.namespace_uri)
    }
  }
  result
}

///|
/// Append independently scoped graphs. Imported key IDs and global graph IDs get a prefix.
/// Different root descriptions or conflicting root extension attributes are errors, not lost data.
pub fn Document::merge(
  self : Document,
  other : Document,
  prefix : String,
  limits? : Limits = Limits::default(),
) -> MergeResult raise GraphError {
  valid_token(prefix, "merge.prefix")
  let catalog = key_map(self.keys)
  let key_mapping : Map[String, String] = Map([])
  let keys = self.keys.copy()
  for key in other.keys {
    let id = prefix + key.id
    require(
      !catalog.contains(id),
      "merge.key",
      "prefixed key collides with existing declaration",
    )
    key_mapping[key.id] = id
    keys.push({ ..key, id, })
  }
  let description = match (self.description, other.description) {
    (None, right) => right
    (left, None) => left
    (Some(left), Some(right)) => {
      require(
        left == right,
        "merge.desc",
        "different document descriptions require an explicit application policy",
      )
      Some(left)
    }
  }
  let extra = merge_root_attributes(self.extra, other.extra)
  let namespaces = merge_root_namespaces(self, other)
  let rewrite = fn(datum : Datum) {
    { ..datum, key: key_mapping.get(datum.key).unwrap(), }
  }
  let graph_mapping : Map[String, String] = Map([])
  let graphs = self.graphs.copy()
  let imported_roots = []
  for graph in other.graphs {
    imported_roots.push(graphs.length())
    graphs.push(
      prefix_graph_ids(map_graph_data(graph, rewrite), prefix, graph_mapping),
    )
  }
  let data = self.data.copy()
  data.append(other.data.map(rewrite))
  let document = Document::new(
    keys,
    graphs,
    data~,
    description?,
    extra~,
    namespaces~,
    limits~,
  )
  { document, imported_roots, key_mapping, graph_mapping, }
}
