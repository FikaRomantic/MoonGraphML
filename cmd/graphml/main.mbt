///|
fn main {
  let args = @env.args()
  if args.length() != 3 ||
    (
      args[1] != "roundtrip" &&
      args[1] != "inspect" &&
      args[1] != "generate" &&
      args[1] != "verify"
    ) {
    println(
      "usage: graphml roundtrip|inspect|verify INPUT.graphml OR graphml generate SEED",
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
  let document = @gml.parse(input) catch {
    error => {
      println("ERROR: \{error.message()}")
      @sys.exit(1)
      return
    }
  }
  if args[1] == "roundtrip" || args[1] == "verify" {
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
