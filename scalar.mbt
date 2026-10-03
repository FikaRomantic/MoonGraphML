///|
pub(all) enum ValueType {
  Boolean
  Int32
  Int64
  Float32
  Float64
  StringValue
} derive(Eq, @debug.Debug)

///|
pub extend ValueType with Eq::{equal, not_equal}

///|
pub extend ValueType with @debug.Debug::{to_repr}

///|
pub(all) enum Scalar {
  BooleanValue(Bool)
  IntegerValue(Int)
  LongValue(Int64)
  FloatValue(Float)
  DoubleValue(Double)
  TextValue(String)
} derive(@debug.Debug)

///|
pub extend Scalar with @debug.Debug::{to_repr}

///|
pub fn ValueType::from_name(name : String) -> ValueType raise GraphError {
  match name {
    "boolean" => Boolean
    "int" => Int32
    "long" => Int64
    "float" => Float32
    "double" => Float64
    "string" => StringValue
    _ => raise InvalidGraph(path="key.attr.type", reason="unknown type \{name}")
  }
}

///|
pub fn ValueType::name(self : ValueType) -> String {
  match self {
    Boolean => "boolean"
    Int32 => "int"
    Int64 => "long"
    Float32 => "float"
    Float64 => "double"
    StringValue => "string"
  }
}

///|
fn decimal_integer(text : String, path : String) -> Unit raise GraphError {
  require(text.length() > 0, path, "empty integer")
  let first = text.code_unit_at(0)
  let start = if first == 43 || first == 45 { 1 } else { 0 }
  require(start < text.length(), path, "integer requires digits")
  for i = start; i < text.length(); i = i + 1 {
    let c = text.code_unit_at(i)
    require(c >= 48 && c <= 57, path, "invalid decimal integer")
  }
}

///|
fn floating_lexical(text : String, path : String) -> Unit raise GraphError {
  if text == "INF" || text == "-INF" || text == "NaN" {
    return
  }
  require(text.length() > 0, path, "empty floating-point value")
  let mut position = 0
  if text.code_unit_at(0) == 43 || text.code_unit_at(0) == 45 {
    position = 1
  }
  let mut digits = 0
  while position < text.length() &&
        text.code_unit_at(position) >= 48 &&
        text.code_unit_at(position) <= 57 {
    digits = digits + 1
    position = position + 1
  }
  if position < text.length() && text.code_unit_at(position) == 46 {
    position = position + 1
    while position < text.length() &&
          text.code_unit_at(position) >= 48 &&
          text.code_unit_at(position) <= 57 {
      digits = digits + 1
      position = position + 1
    }
  }
  require(digits > 0, path, "floating-point value requires digits")
  if position < text.length() &&
    (text.code_unit_at(position) == 69 || text.code_unit_at(position) == 101) {
    position = position + 1
    if position < text.length() &&
      (text.code_unit_at(position) == 43 || text.code_unit_at(position) == 45) {
      position = position + 1
    }
    let exponent_start = position
    while position < text.length() &&
          text.code_unit_at(position) >= 48 &&
          text.code_unit_at(position) <= 57 {
      position = position + 1
    }
    require(position > exponent_start, path, "exponent requires digits")
  }
  require(
    position == text.length(),
    path,
    "invalid floating-point lexical value",
  )
}

///|
fn read_double(text : String, path : String) -> Double raise GraphError {
  floating_lexical(text, path)
  match text {
    "INF" => 1.0 / 0.0
    "-INF" => -1.0 / 0.0
    "NaN" => 0.0 / 0.0
    _ => {
      let value = @string.parse_double(text) catch {
        _ => raise InvalidGraph(path~, reason="floating-point overflow")
      }
      require(!value.is_inf(), path, "finite floating-point value overflow")
      value
    }
  }
}

///|
pub fn Scalar::parse(
  kind : ValueType,
  authored : String,
) -> Scalar raise GraphError {
  if kind == StringValue {
    return TextValue(authored)
  }
  let text = authored.trim(chars=" \t\r\n").to_owned()
  let path = "data.\{kind.name()}"
  match kind {
    Boolean =>
      match text {
        "true" | "1" => BooleanValue(true)
        "false" | "0" => BooleanValue(false)
        _ => raise InvalidGraph(path~, reason="expected true, false, 1 or 0")
      }
    Int32 => {
      decimal_integer(text, path)
      let value = @string.parse_int(text) catch {
        _ => raise InvalidGraph(path~, reason="32-bit integer overflow")
      }
      IntegerValue(value)
    }
    Int64 => {
      decimal_integer(text, path)
      let value = @string.parse_int64(text) catch {
        _ => raise InvalidGraph(path~, reason="64-bit integer overflow")
      }
      LongValue(value)
    }
    Float32 => {
      let value = read_double(text, path)
      let single = Float::from_double(value)
      require(
        value.is_inf() || !single.to_double().is_inf(),
        path,
        "32-bit floating-point overflow",
      )
      FloatValue(single)
    }
    Float64 => DoubleValue(read_double(text, path))
    StringValue => TextValue(authored)
  }
}

///|
pub fn Scalar::value_type(self : Scalar) -> ValueType {
  match self {
    BooleanValue(_) => Boolean
    IntegerValue(_) => Int32
    LongValue(_) => Int64
    FloatValue(_) => Float32
    DoubleValue(_) => Float64
    TextValue(_) => StringValue
  }
}

///|
fn double_text(value : Double) -> String {
  if value.is_nan() {
    "NaN"
  } else if value.is_inf() {
    if value < 0.0 {
      "-INF"
    } else {
      "INF"
    }
  } else {
    value.to_string()
  }
}

///|
pub fn Scalar::lexical(self : Scalar) -> String {
  match self {
    BooleanValue(value) => if value { "true" } else { "false" }
    IntegerValue(value) => value.to_string()
    LongValue(value) => value.to_string()
    FloatValue(value) => double_text(value.to_double())
    DoubleValue(value) => double_text(value)
    TextValue(value) => value
  }
}

///|
pub fn Scalar::equivalent(self : Scalar, other : Scalar) -> Bool {
  if self.value_type() != other.value_type() {
    return false
  }
  match (self, other) {
    (BooleanValue(a), BooleanValue(b)) => a == b
    (IntegerValue(a), IntegerValue(b)) => a == b
    (LongValue(a), LongValue(b)) => a == b
    (FloatValue(a), FloatValue(b)) =>
      a == b || (a.to_double().is_nan() && b.to_double().is_nan())
    (DoubleValue(a), DoubleValue(b)) => a == b || (a.is_nan() && b.is_nan())
    (TextValue(a), TextValue(b)) => a == b
    _ => false
  }
}
