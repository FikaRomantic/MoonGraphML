# GraphML compatibility and interoperability

MoonGraphML implements a supported GraphML information model, not a complete
XML Schema engine or every vendor extension. The normative source is the
[GraphML specification and schemas](http://graphml.graphdrawing.org/specification.html);
the [GraphML primer](http://graphml.graphdrawing.org/primer/graphml-primer.html)
is useful explanatory material. GraphML namespace matching uses expanded names,
not literal prefixes.

## Implemented model

| Capability | MoonGraphML behavior |
| --- | --- |
| Scalar declarations | boolean, signed 32/64-bit integers, float/double, string |
| Defaults | Declarations, wrapper attributes, and namespace context retained; resolved only on request |
| Direction | Directed, undirected, and per-edge overrides/mixed graphs |
| Binary structure | Parallel edges and self-loops retained |
| Hierarchy | Graphs nested in nodes, edges, or hyperedges |
| Ports | Hierarchical port declarations and checked references |
| Hyperedges | Endpoints with in/out/undir direction and optional ports |
| XML payloads | Untyped data/defaults retain expanded names, text, and in-scope QName context |
| Locators | Namespaced XLink metadata retained; never automatically fetched |
| Parse hints | Lexically checked; explicit flat count/ID checks are available |

Required fields, element ordering, duplicate identifiers/data keys, key scopes,
numeric ranges, dangling references, and configured budgets are checked.
Application-specific schemas are not loaded or validated. Arbitrary foreign
structural child elements are rejected; application XML belongs inside untyped
`data` or `default` payloads. Unknown extra attributes are retained as expanded
names and values, not interpreted as proof of vendor-schema compliance.
XML local names/prefixes must be NCNames, while GraphML identifiers and
`attr.name` use NMTOKEN rules. GraphML `desc` accepts plain text only: attributes
(including `xml:lang`) and nested elements are rejected. Namespace declarations
are not data attributes; duplicate expanded attribute names and reserved
namespace/prefix misuse are rejected.

Output preserves the supported model, not original source bytes. Structural
GraphML prefixes, XML attribute-prefix spelling, whitespace between structural
elements, entity/CDATA spelling, comments, and processing instructions need not
survive. Payload-element prefixes and their in-scope bindings are retained to
keep inherited/default QName contexts stable; generated attribute prefixes avoid
colliding with saved bindings. Defaults retain wrapper attributes and bindings
through `Key.default_extra` and `Key.default_namespaces`. Scalar numbers may use
a different equivalent lexical representation. Nodes are emitted before edges;
an existing graph `parse.order` is regenerated as `nodesfirst`. Count, degree,
and canonical-ID hints are preserved and can become stale after transformations.

Namespace-context retention is not vendor-schema interpretation. The library
does not resolve arbitrary QName-valued strings, rewrite embedded references,
or prove that a QName value names a declared application type. Equivalence uses
a conservative prefix-occurrence check, including the default namespace of
unprefixed `xsi:type`; it does not infer every unprefixed application value's
type. GraphML structural containers, data, locators, keys, and the document root
also retain their own in-scope contexts. This includes a namespace prefix used
only by a container's `xsi:type` value. Root merging conservatively rejects
conflicting contexts when both roots carry opaque extra values; it does not
guess that an unprefixed value is unrelated to namespaces.

## Read profiles

`Strict` is the default for the library and CLI `roundtrip`, `inspect`, and
`verify`. For example, typed booleans use `true`, `false`, `1`, or `0`; special
float/double values use `INF`, `-INF`, and `NaN`.

`ReferenceLibraries` is opt-in through `parse(..., profile=ReferenceLibraries)`
or CLI `roundtrip-compatible`. It additionally normalizes `True`/`False` and
`inf`/`-inf`/`nan` within typed data/defaults, because selected reference-tool
writers emit those spellings. It leaves strings and XML payloads unchanged.
Serialized output uses the supported standard spellings. Compatibility mode is
not permission to accept malformed XML, undefined references, or wrong scopes.

## Independent comparisons

The original `scripts/interop.py` compares MoonGraphML with installed,
independent reference libraries; no reference implementation is copied into
the library. The recorded run used NetworkX **3.6.1** and python-igraph **1.0.0**:

| Reference | Cases | Directions per case | Failed directional checks |
| --- | ---: | ---: | ---: |
| NetworkX | 500 | 2 | 0 |
| python-igraph | 300 | 2 | 0 |

There are 1,600 directional checks in total. Each case runs reference-generated
GraphML through MoonGraphML and back into the reference reader, and runs a
MoonGraphML-emitted graph through the reference writer and back. The comparison
checks the declared scalar graph semantics, not byte equality. These numbers
describe a completed corpus run, not universal compatibility or a performance
guarantee.

### NetworkX profile

The common profile is a flat, uniformly directed or uniformly undirected
multigraph with scalar graph/node/edge attributes, self-loops, parallel-edge
identity, Unicode text, defaults, and integer values including values above
JavaScript's exact-double range. Node IDs, endpoints, effective direction,
parallel multiplicity/keys, and resolved attributes are compared. Key declaration
IDs, unused declarations, XML metadata, and source spelling are outside the
comparison.

NetworkX keeps node/edge defaults separately rather than applying them to
every item. The suite explicitly expands applicable defaults before reference
re-export so it compares effective values. This is an interoperability adapter
policy, not a change to MoonGraphML's default storage semantics. NetworkX's
GraphML implementation does not support mixed direction, nested graphs, ports,
or hyperedges; those are tested by MoonGraphML's own structural tests, not this
comparison. See the [NetworkX GraphML reference](https://networkx.org/documentation/stable/reference/readwrite/graphml.html)
and [read_graphml default-value notes](https://networkx.org/documentation/stable/reference/readwrite/generated/networkx.readwrite.graphml.read_graphml.html).

### igraph profile

The compared profile is flat scalar multigraphs with uniform direction,
self-loops, parallel edges, Unicode strings, booleans, and finite double values.
igraph represents numeric attributes as floating-point values; arbitrary
64-bit integer precision is **not** part of the claim. Vertex positions,
normalized endpoints, multiplicity, and scalar graph/vertex/edge attributes are
compared. Its materialized/generated `id` attributes are retained according to
the reference baseline rather than mistaken for unchanged GraphML key/element
IDs. Tests also check the reference's own re-export baseline before checking
MoonGraphML's recovered output.

No compatibility claim is made here for mixed graphs, ports, hyperedges,
hierarchy, XML payloads, unresolved locators, or nonfinite numbers through
igraph. See [igraph's GraphML reader/writer documentation](https://igraph.org/c/doc/igraph-Foreign.html#graphml-format).

### Reproducing the differential suite

Install the Python reference tools separately from the MoonBit runtime:

```sh
python -m pip install -r scripts/requirements-interop.txt
moon build --target native --release --deny-warn
python scripts/interop.py --exe _build/native/release/build/cmd/graphml/graphml.exe
```

On Unix, pass the actual native binary path without the Windows `.exe` suffix.
The script creates fixtures/results only under ignored `.local/`; it exits on
an assertion or subprocess failure. It uses bounded igraph worker batches to
avoid the Windows reference binary exhausting file descriptors. No case is
silently skipped. Python tools are required only for this development check,
not for using the MoonBit library.

The separate `scripts/standards.py` uses unmodified, hash-pinned official XSDs
and an original strict extension vocabulary. It checks advanced structures,
expected rejection diagnostics, deterministic serialization, and namespace
contexts against independent XSD engines. Run it without `--offline` initially
to cache official schemas; subsequent offline runs use `.local/graphml-schema`.
`xmlschema` 4.3.2 with `elementpath` 5.1.4 is its ordinary-corpus oracle;
`lxml` independently validates legal `xsi:type` instances and deliberately
unbound-QName counterexamples. Proven engine disagreements are separately
recorded rather than deleting identity constraints or weakening the schemas.
This does not make MoonGraphML itself an XSD engine.
`texttable` 1.7.0 is a development-only transitive dependency of python-igraph.
Their licenses and sources are listed in [third-party notices](../THIRD_PARTY_NOTICES.md).

`python scripts/benchmark.py` runs three fresh native `inspect` processes for
each of 1,000/10,000/100,000 nodes and five times as many edges. It asserts stored
counts and structural flags and records elapsed wall time, throughput, child
peak working set/RSS, hardware, toolchain, and input/binary hashes only under
`.local/`. Timing includes startup, file IO/decode, parsing/validation,
statistics and shutdown; it is not a parser-only or reference-speed comparison.
On Windows memory uses the OS lifetime `PeakWorkingSetSize`; on Linux the sampled
VmHWM is explicitly a lower bound. Missing measurements are not reported as zero.

## Security and operational limits

DTD declarations are rejected before invoking the XML parser. GraphML locators,
schema-location attributes, and extension URLs are metadata: the library does
not access the network, resolve external files, or execute extension content.
The XML dependency handles syntax and namespaces, while MoonGraphML checks its
own depth, event, text, attribute, structure-count, and output-byte budgets.

These are in-memory ceilings, not an operating-system memory quota or timeout.
The CLI reads a file into a string before the library can inspect its size.
Hosts that accept untrusted uploads should enforce request/file-size and
process/time limits as well. XML payloads may contain application-sensitive
information even when structurally valid; sanitize according to the destination
application's policy before display or execution. MoonGraphML does not promise
full XSD validation, constant-memory streaming, or immunity from every bug in
the XML dependency.
