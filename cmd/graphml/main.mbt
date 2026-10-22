///|
fn main {
  let args = @env.args()
  if args.length() < 3 ||
    (
      args[1] != "roundtrip" &&
      args[1] != "roundtrip-compatible" &&
      args[1] != "inspect" &&
      args[1] != "generate" &&
      args[1] != "verify" &&
      args[1] != "subgraph" &&
      args[1] != "csr" &&
      args[1] != "csr-incoming"
    ) ||
    (args.length() != 3 && args[1] != "subgraph") {
    println(
      "usage: graphml roundtrip|roundtrip-compatible|inspect|verify|csr|csr-incoming INPUT.graphml OR graphml subgraph INPUT.graphml [NODE_ID ...] OR graphml generate SEED",
    )
    @sys.exit(2)
    return
  }
  if args[1] == "generate" {
    let seed = @string.parse_int(args[2]) catch {
      _ => {
        println("ERROR: seed must be an integer")
        @sys.exit(2)
        return
      }
    }
    let output = generate(seed) catch {
      error => {
        println("ERROR: \{error.message()}")
        @sys.exit(1)
        return
      }
    }
    println(output)
    return
  }
  let input = @fs.read_file_to_string(args[2]) catch {
    error => {
      let @fs.IOError(message) = error
      println("ERROR: \{message}")
      @sys.exit(1)
      return
    }
  }
  let profile = if args[1] == "roundtrip-compatible" {
    @gml.ReferenceLibraries
  } else {
    @gml.Strict
  }
  let document = @gml.parse(input, profile~) catch {
    error => {
      println("ERROR: \{error.message()}")
      @sys.exit(1)
      return
    }
  }
  if args[1] == "subgraph" || args[1] == "csr" || args[1] == "csr-incoming" {
    let output = export_selection(document, args) catch {
      error => {
        println("ERROR: \{error.message()}")
        @sys.exit(1)
        return
      }
    }
    println(output)
    return
  }
  if args[1] == "roundtrip" ||
    args[1] == "roundtrip-compatible" ||
    args[1] == "verify" {
    let output = @gml.serialize(document) catch {
      error => {
        println("ERROR: \{error.message()}")
        @sys.exit(1)
        return
      }
    }
    if args[1] == "verify" {
      let recovered = @gml.parse(output) catch {
        error => {
          println("ERROR: \{error.message()}")
          @sys.exit(1)
          return
        }
      }
      if !document.equivalent(recovered) {
        println("ERROR: model changed during roundtrip")
        @sys.exit(1)
        return
      }
      println("OK: model-equivalent roundtrip")
    } else {
      println(output)
    }
  } else {
    let stats = document.statistics()
    println(
      "graphs=\{stats.graphs} nodes=\{stats.nodes} edges=\{stats.edges} hyperedges=\{stats.hyperedges} ports=\{stats.ports} endpoints=\{stats.endpoints}",
    )
    println(
      "mixed=\{stats.has_mixed_direction} parallel=\{stats.has_parallel_edges} loops=\{stats.has_self_loops} locators=\{stats.has_locators} xml_payloads=\{stats.has_xml_payloads}",
    )
  }
}

///|
fn export_selection(
  document : @gml.Document,
  args : Array[String],
) -> String raise @gml.GraphError {
  if document.graph_count() != 1 {
    raise @gml.Unsupported(
      path="cli.graph",
      feature="select exactly one root with the library interface before exporting",
    )
  }
  let flat = document.flat_graph(@gml.GraphAddress::root(0))
  if args[1] == "subgraph" {
    let selection = []
    for i = 3; i < args.length(); i = i + 1 {
      selection.push(args[i])
    }
    return @gml.serialize(flat.induced_subgraph(selection))
  }
  let csr = flat.to_csr(
    orientation=if args[1] == "csr-incoming" {
      @gml.Incoming
    } else {
      @gml.Outgoing
    },
  )
  let output : Json = {
    "node_ids": @json.to_json(csr.node_ids()),
    "indptr": @json.to_json(csr.indptr()),
    "indices": @json.to_json(csr.indices()),
    "edge_indices": @json.to_json(csr.edge_indices()),
    "reversed": @json.to_json(csr.reversed()),
    "orientation": if args[1] == "csr-incoming" {
      "incoming"
    } else {
      "outgoing"
    },
  }
  output.stringify()
}
