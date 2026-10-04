///|
fn read_port(
  element : XmlElementValue,
  keys : Map[String, Key],
  budget : ParseBudget,
) -> Port raise GraphError {
  graphml_element(element, "port")
  check_bound("ports", budget.ports + 1, budget.limits.ports)
  budget.ports = budget.ports + 1
  let children = element_children(element)
  let port : Port = {
    name: required_attribute(element, "name"),
    description: read_description(children, "port"),
    data: [],
    ports: [],
    extra: extra_attributes(element, ["name"]),
  }
  for child in children {
    require(
      child.namespace_uri == Some(GRAPHML_URI),
      "port",
      "unknown child namespace",
    )
    match child.name {
      "desc" => ()
      "data" => port.data.push(read_datum(child, keys))
      "port" => port.ports.push(read_port(child, keys, budget))
      _ => raise Unsupported(path="port", feature=child.name)
    }
  }
  port
}

///|
fn collect_ports(
  ports : Array[Port],
  names : Map[String, Bool],
  catalog : Map[String, Key],
) -> Unit raise GraphError {
  for port in ports {
    valid_token(port.name, "port.name")
    require(
      !names.contains(port.name),
      "port.name",
      "duplicate port \{port.name}",
    )
    names[port.name] = true
    check_data(port.data, PortScope, catalog)
    collect_ports(port.ports, names, catalog)
  }
}

///|
fn check_port_reference(
  port : String?,
  node : String,
  node_ports : Map[String, Map[String, Bool]],
) -> Unit raise GraphError {
  if port is Some(name) {
    valid_token(name, "port.reference")
    let names = node_ports.get(node).unwrap_or(Map([]))
    require(
      names.contains(name),
      "port.reference",
      "missing port \{node}:\{name}",
    )
  }
}
