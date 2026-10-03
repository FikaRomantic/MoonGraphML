///|
/// A scoped, owned view of explicit attributes and key defaults.
pub struct Attributes {
  scope : Scope
  keys : Array[Key]
  catalog : Map[String, Key]
  explicit : Map[String, Datum]
}

///|
pub fn Attributes::new(
  doc : Document,
  scope : Scope,
  data : Array[Datum],
) -> Attributes raise GraphError {
  require(
    scope != All && scope != EndpointScope,
    "attributes.scope",
    "scope must name an element that accepts data",
  )
  let catalog = key_map(doc.keys)
  check_data(data, scope, catalog)
  let explicit : Map[String, Datum] = Map([])
  for datum in clone_data(data) {
    explicit[datum.key] = datum
  }
  { scope, keys: doc.keys, catalog, explicit, }
}

///|
fn Attributes::check_key(
  self : Attributes,
  id : String,
) -> Key raise GraphError {
  let key = match self.catalog.get(id) {
    Some(key) => key
    None =>
      raise InvalidGraph(path="attributes.key", reason="undefined key \{id}")
  }
  require(
    key.scope.applies_to(self.scope),
    "attributes.scope",
    "key scope does not apply",
  )
  key
}

///|
/// Omitted values are resolved from defaults only when requested; explicit empties remain empty.
pub fn Attributes::get(
  self : Attributes,
  id : String,
  use_default? : Bool = true,
) -> DataValue? raise GraphError {
  let key = self.check_key(id)
  match self.explicit.get(id) {
    Some(datum) => Some(clone_value(datum.value))
    None => if use_default { key.default_value.map(clone_value) } else { None }
  }
}

///|
pub fn Attributes::scalar(
  self : Attributes,
  id : String,
  use_default? : Bool = true,
) -> Scalar? raise GraphError {
  match self.get(id, use_default~) {
    Some(ScalarValue(value)) => Some(value)
    None => None
    Some(XmlPayload(_)) =>
      raise Unsupported(path="attributes.scalar", feature="extension XML value")
  }
}

///|
/// Attribute names are not necessarily unique. Ambiguity is an error, never an arbitrary choice.
pub fn Attributes::key_by_name(
  self : Attributes,
  name : String,
) -> String? raise GraphError {
  let mut result : String? = None
  for key in self.keys {
    if key.scope.applies_to(self.scope) && key.name == Some(name) {
      require(
        result is None,
        "attributes.name",
        "ambiguous attribute name \{name}",
      )
      result = Some(key.id)
    }
  }
  result
}

///|
pub fn Attributes::contains_explicit(
  self : Attributes,
  id : String,
) -> Bool raise GraphError {
  let _ = self.check_key(id)
  self.explicit.contains(id)
}

///|
/// Resolve in declaration order, keeping explicit data metadata and adding applicable defaults.
pub fn Attributes::resolved(self : Attributes) -> Array[Datum] {
  let result = []
  for key in self.keys {
    if key.scope.applies_to(self.scope) {
      match self.explicit.get(key.id) {
        Some(datum) => result.append(clone_data([datum]))
        None =>
          if key.default_value is Some(value) {
            result.push({
              key: key.id,
              id: None,
              value: clone_value(value),
              extra: [],
            })
          }
      }
    }
  }
  result
}
