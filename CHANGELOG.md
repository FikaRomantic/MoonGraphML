# Changelog

## Unreleased local-readiness work

- Preserve namespace context for all GraphML containers, including QName-only
  bindings on core `xsi:type`, as well as payload/default wrappers.
- Reject ambiguous root-context merges without rewriting opaque values.
- Avoid repeated all-declaration scans for sparse typed tables; retain stable
  declaration ordering and complete validation.
- Bound serializer attribute/namespace counts and aggregate direct text, and
  reject malformed Unicode in standalone scalar parsing.
- Add public API pipeline regressions and offline package/history safeguards.

## 0.1.0 — local development, unreleased

- Added bounded namespace-aware GraphML import/export and typed scalar keys,
  defaults, scoped attributes, and structured errors.
- Added directed/undirected/mixed binary graphs, parallel edges, self-loops,
  nested graphs, hierarchical ports, hyperedges, and non-fetching locators.
- Added owned documents, stable structural addresses, ID/incident indexes,
  attribute/default views, scalar rows, positional edge adapters, and a batch
  flat-graph builder.
- Added validated immutable key/node/port renaming, node/edge/graph replacement,
  root selection, and prefix-mapped document merging.
- Added structural statistics, semantic equivalence, parse-hint access, and
  explicit reference-library scalar compatibility mode.
- Retained inherited QName namespace context in XML payloads and key-default
  wrapper metadata; added binding-aware equivalence and safe prefix generation.
- Added NCName validation, reserved namespace checks, duplicate expanded-name
  rejection, plain-text description checks, and bounded `Attributes` ownership.
- Added three executable workflow examples, a native CLI, unit/boundary tests,
  and independent NetworkX/igraph differential checks for a declared flat subset.
- Added technical API/compatibility guides, third-party notices, and CI gates
  for all-target checking/building/testing, formatting, interfaces, and examples.
- Documented development-only schema/XPath/reference-tool dependencies without
  making them MoonBit runtime dependencies or copying their implementations.

The local namespace remains `local/moongraphml`; no remote repository,
Mooncakes publication, or remotely successful CI run is implied by this entry.
