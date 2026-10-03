///|
fn main {
  let args = @env.args()
  if args.length() != 3 || (args[1] != "roundtrip" && args[1] != "inspect") {
    println("usage: graphml roundtrip|inspect INPUT.graphml")
    @sys.exit(2)
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
  if args[1] == "roundtrip" {
    let output = @gml.serialize(document) catch {
      error => {
        println("ERROR: \{error.message()}")
        @sys.exit(1)
        return
      }
    }
    println(output)
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
