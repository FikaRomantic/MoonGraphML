///|
/// Human-readable diagnostics for command-line/UI presentation; variants remain machine-readable.
pub fn GraphError::message(self : GraphError) -> String {
  match self {
    InvalidXml(message) => "invalid XML: \{message}"
    InvalidGraph(path~, reason~) => "\{path}: \{reason}"
    LimitExceeded(resource~, limit~) =>
      "resource limit exceeded: \{resource} (limit \{limit})"
    Unsupported(path~, feature~) => "\{path}: unsupported \{feature}"
  }
}
