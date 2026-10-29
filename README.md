# MoonGraphML

MoonBit-native GraphML graph-data interchange: read, validate, build, transform,
and write graph documents with typed attributes and explicit resource limits.
It connects MoonBit applications to existing graph-data workflows without
reimplementing graph algorithms or visual layout.

Module: `FikaRomantic/moongraphml`, version `0.2.0`.
Source: [FikaRomantic/MoonGraphML](https://github.com/FikaRomantic/MoonGraphML).
Repository owner, maintenance commit identity and publishing account:
`FikaRomantic`.

```sh
moon add FikaRomantic/moongraphml@0.2.0
```

## New in 0.2.0

- `Document::relabel_nodes` atomically renames a batch of node IDs, including swaps and cycles, while preserving structural edge and hyperedge references.
- `FlatGraph::edge_subgraph` selects edges by source ordinal, retaining individual anonymous/parallel edges and optionally isolated nodes.

Requires **moonc >= 0.10.16**. Relabeling does not interpret opaque XML business references; edge selection follows the existing flat-graph scope. See the [API, limits and complexity notes](docs/FEATURE_EXTENSIONS.md).

```sh
moon run examples/selection --target wasm-gc --deny-warn
```

## Where it fits

- Software and data engineering: exchange service dependencies, build graphs,
  and data-pipeline relationships with external analysis tools.
- Network and asset management: represent device links, named ports, nested
  topology, and multi-party connections using hyperedges.
- Research and data analysis: move typed relationship datasets between MoonBit
  applications and Python/R graph-analysis workflows, retaining parallel edges,
  self-loops, and explicit direction.

## Features and boundaries

The library supports GraphML key declarations, six scalar types, scoped defaults,
directed/undirected/mixed binary edges, parallel edges, self-loops, hierarchical
graphs, hierarchical ports, and hyperedge endpoints. It validates identifiers,
key scopes/types, references, child ordering, and configured resource budgets.
Owned documents, address/ID indexes, typed table views, batch construction,
reference-aware renaming, graph replacement/selection, node-induced subgraph
extraction, document merging, and edge-mapped CSR adjacency exports are
available through the [API guide](docs/API.md).

Owned readonly wrappers (`Document`, `FlatGraph`, `GraphIndex`, `Attributes`,
`CsrAdjacency` and builders) keep their representation private. Use their
public methods rather than accessing fields; returned graph/array views are
detached. The explicit `pub(all)` raw construction records remain editable.

Custom XML attribute data preserves expanded names (namespace URI plus local
name), attributes, text, payload-element prefixes, and in-scope namespace
bindings. GraphML containers also retain their namespace contexts and extra
attributes. This retains context for opaque QName values such as
`xsi:type="p:Rectangle"`, including inherited bindings and default-namespace
resets. Key defaults separately retain their wrapper attributes and namespace
context. The library does not interpret or schema-validate these QName values.
Structural GraphML prefixes and attribute-prefix spelling may change; comments,
processing instructions, CDATA spelling, and source bytes are not preserved.
Serialization is deterministic for a given document, not XML canonicalization
or graph isomorphism. Nodes are emitted before edges; an existing `parse.order`
hint is updated to `nodesfirst`. Other parse hints are preserved, not
automatically recomputed after every transformation.

XML parsing buffers the document in memory. This is not a constant-memory
streaming parser, complete XML Schema validator, layout engine, or graph
algorithm framework. DTD declarations are rejected. External GraphML locators
are retained as metadata and never fetched; application-defined XML is not
interpreted or executed. XML local names/prefixes must be NCNames, GraphML
identifier/name tokens must satisfy their NMTOKEN rules, and GraphML `desc`
elements with attributes or child elements are rejected. See
[compatibility and security limits](docs/COMPATIBILITY.md).

## Build and run locally

Install the [MoonBit toolchain](https://www.moonbitlang.com/download/), then run
these commands from the project directory:

```sh
moon update
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
```

This revision is tested with `moonc v0.10.16+b1a0e846e` and the 2026-10-16
`moon`/`moonrun`. On Windows, that particular driver/compiler pair can fail
on generated `\\?\` output paths before checking project code. A project-local
adapter normalizes only extended drive-path arguments and still invokes the
installed 0.10.16 compiler; it does not modify the toolchain or dependencies:

```powershell
pwsh -NoProfile -File scripts/Invoke-Moon016.ps1 check --target all --deny-warn --frozen
pwsh -NoProfile -File scripts/Invoke-Moon016.ps1 build --target all --deny-warn --frozen
pwsh -NoProfile -File scripts/Invoke-Moon016.ps1 test --target all --deny-warn --frozen
pwsh -NoProfile -File scripts/Invoke-Moon016.ps1 fmt
```

The same normalization is applied to `moonfmt` when formatting. The adapter
requires Windows .NET Framework's C# compiler and is restricted to
0.10.16. Use normal commands on unaffected toolchains; `--frozen` additionally
requires dependencies already resolved by `moon update`. The adapter and all
generated files remain development-only and are excluded from the Moon package.

Five executable examples exercise different workflows:

```sh
moon run --target native --deny-warn examples/dependencies
moon run --target native --deny-warn examples/topology
moon run --target native --deny-warn examples/datasets
moon run --target native --deny-warn examples/analytics
moon run --target native --deny-warn examples/selection
```

`dependencies` builds a service graph, checks import/export equivalence, and
looks up an incident edge. `topology` renames a port while updating binary-edge
and hyperedge references. `datasets` resolves typed defaults into rows and
merges separately scoped graph documents. `analytics` extracts a service subset,
exports outgoing/incoming CSR, and joins edge ordinals to exact Int64 weights
and defaults without merging parallel relationships. Each example has assertions.

## Library usage

Import the module in your consuming package's `moon.pkg`:

```moonbit
import {
  "FikaRomantic/moongraphml" @graphml,
}
```

A minimal executable can use the same API as the dependency example:

Set `pkgtype(kind: "executable")` in that executable package's `moon.pkg` and
place the following entry point in `main.mbt`:

```moonbit
fn main raise {
  let builder = try! @graphml.FlatBuilder::new([], @graphml.Directed)
  try! builder.add_node("api")
  try! builder.add_node("database")
  try! builder.add_edge("api", "database", id="uses")
  let document = try! builder.finish()
  let xml = try! @graphml.serialize(document)
  assert_true(document.equivalent(try! @graphml.parse(xml)))
  println(xml)
}
```

`try!` keeps examples compact. Production callers should catch `GraphError`
and use its variants or `message()` to report invalid data, unsupported
projections, and exceeded budgets. Defaults remain declarations until requested
through `Attributes` or a typed row view; they are not silently materialized.

## Selecting graph data and exporting adjacency

```moonbit
let flat = try! document.flat_graph(@graphml.GraphAddress::root(0))
let selected = try! flat.induced_subgraph(["api", "database"])
let selected_flat = try! selected.flat_graph(@graphml.GraphAddress::root(0))
let csr = try! selected_flat.to_csr(orientation=@graphml.Incoming)
let database = csr.node_index("database").unwrap()
let dependencies = try! csr.row(database)
```

Induced extraction keeps source order and every edge with both endpoints selected,
including loops and parallel edges. It preserves keys/defaults, graph/node/edge
attributes and XML contexts; unknown or duplicate selections are errors. Stale
unqualified `parse.*` hints are removed from the graph and selected nodes. This
selected-graph operation does not include document-root metadata or rewrite
application references embedded in opaque XML.

CSR uses `indptr`/`indices` plus `node_ids`, `edge_indices` and `reversed` mapping
arrays. Parallel entries are retained, not summed; rows follow original edge
order, so columns are not necessarily sorted. Undirected non-loops emit two
arcs, undirected loops one. `Incoming` reverses directed arcs. Join original edge
attributes by `edge_indices`, rather than coercing all weights to floating point.
`max_arcs` defaults to 2,000,000 and is checked before arc-buffer allocation.
Both features require an existing lossless `FlatGraph` view and do not silently
flatten advanced structures. See [precise contracts and costs](docs/API.md).

## Command-line tool

The CLI reads UTF-8 GraphML files. `roundtrip`, `inspect`, and `verify` use the
strict read profile by default; there is no separate `strict` subcommand.

```sh
moon run --target native --deny-warn cmd/graphml -- inspect tests/fixtures/flat.graphml
moon run --target native --deny-warn cmd/graphml -- verify tests/fixtures/flat.graphml
moon run --target native --deny-warn cmd/graphml -- roundtrip tests/fixtures/flat.graphml
moon run --target native --deny-warn cmd/graphml -- roundtrip-compatible tests/fixtures/flat.graphml
moon run --target native --deny-warn cmd/graphml -- generate 7
moon run --target native --deny-warn cmd/graphml -- subgraph tests/fixtures/flat.graphml a b
moon run --target native --deny-warn cmd/graphml -- csr tests/fixtures/flat.graphml
moon run --target native --deny-warn cmd/graphml -- csr-incoming tests/fixtures/flat.graphml
```

`inspect` prints stored counts and structural flags. `verify` checks
model-equivalent serialization/reparsing. `roundtrip` emits normalized GraphML.
`roundtrip-compatible` explicitly tolerates selected reference-library scalar
spellings (`True`/`False`, `inf`/`-inf`/`nan`), without weakening reference or
structure checks. `generate` emits a deterministic test graph for an integer
seed. Usage errors exit with code 2; file, validation, and conversion errors exit
with code 1. Errors currently print to standard output, so check the exit code
before treating captured output as XML.

`subgraph INPUT [NODE_ID ...]` emits GraphML (no IDs means an empty graph).
`csr`/`csr-incoming` emit JSON mapping arrays. These commands require exactly one
root graph and a supported flat structure; they refuse ambiguous/lossy input.

## Interoperability

The reproducible differential suite has passed **500 NetworkX 3.6.1 cases and
300 python-igraph 1.0.0 cases, two directions per case, with zero failures**.
These 1,600 directional checks cover a declared flat scalar multigraph subset,
not every GraphML feature or every version of either tool. NetworkX defaults
are explicitly expanded before re-export; the igraph subset uses finite doubles
and avoids precision claims for arbitrary 64-bit integers. Generated IDs and
reference-library metadata are treated according to the stated comparison
profile. Details and reproduction commands are in
[COMPATIBILITY.md](docs/COMPATIBILITY.md).

The additional adapter suite passed 100 induced-subgraph comparisons with
NetworkX 3.6.1, 400 outgoing/incoming CSR checks against an independent XML
endpoint scan (including mixed direction), and 9 CLI rejection checks:
`python scripts/adapters_interop.py` after a native CLI build. It uses the same
development dependencies as the main differential suite, not SciPy at runtime.

## Development and licensing

Formatting and public-interface consistency can be checked with `moon fmt` and
`moon info`, followed by `git diff --exit-code`. The included CI installs the
current stable toolchain, checks/builds/tests all targets with warnings denied,
checks formatting/interfaces, and runs the five examples and CLI smoke tests.
Release gates also verify report-free history and consistent maintainer identity.
`python scripts/package_qa.py` packages with `moon package --frozen`, checks the
archive's exclusions, and runs an isolated build/test/examples check without
publishing. `python scripts/release_guard.py` checks source scale, nonempty
history, and report/cache exclusions. Its `--release` mode additionally checks
the real namespace, repository and all author/committer identities. Do not use `moon publish --dry-run` as an
offline package test: publication is an explicit later operation.

The original GraphML implementation is [MIT licensed](LICENSE).
[Milky2018/xml](https://github.com/moonbit-community/xml-mbt) supplies XML syntax
and namespace parsing; `moonbitlang/x` supplies CLI filesystem/process helpers.
Both dependencies are Apache-2.0. NetworkX, igraph, lxml, xmlschema, elementpath,
and texttable are independent development tools or their dependencies, not
copied implementations or MoonBit runtime dependencies. See
[third-party notices](THIRD_PARTY_NOTICES.md) and [changes](CHANGELOG.md).
