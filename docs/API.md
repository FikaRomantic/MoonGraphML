# MoonGraphML API guide

This guide describes the source API under the current local namespace
`FikaRomantic/moongraphml`, imported as `@graphml`. Run `moon info` to regenerate the
compiler's precise public interface when the API changes.

## Reading, writing, and errors

`parse(input, limits?=Limits::default(), profile?=Strict)` returns an owned
`Document` or raises `GraphError`. `serialize(document, limits?)` returns UTF-8
XML text with deterministic element grouping. `inspect_keys(input, limits?)`
reads key declarations but does **not** validate graph bodies or references;
use `parse` to validate a document.

The error variants distinguish malformed XML (`InvalidXml`), invalid graph
data (`InvalidGraph` with a path and reason), exhausted resource budgets
(`LimitExceeded`), and operations without a supported lossless representation
(`Unsupported`). `GraphError::message()` is for human-readable presentation;
matching variants is preferable for program logic.

The default `Strict` profile accepts the supported GraphML scalar lexical
forms. Opt-in `ReferenceLibraries` additionally normalizes boolean `True` and
`False`, and float/double `inf`, `-inf`, and `nan`, only in typed data/defaults.
String values and XML extension payloads are opaque. This profile does not
disable key, scope, identifier, reference, or structural validation.

## Types and declarations

`ValueType` names map to `boolean`, `int`, `long`, `float`, `double`, and `string`.
`Scalar` carries the corresponding typed value. `Scalar::parse(kind, text)`
checks lexical validity and numeric range; `lexical()` writes a supported
spelling. `Scalar::equivalent()` compares values, including matching NaNs,
rather than original spellings.

`Key::new(id, scope, value_type, name?, default_value?, description?)` creates a
typed declaration. Scopes are `All`, `DocumentScope`, `GraphScope`, `NodeScope`,
`EdgeScope`, `PortScope`, `HyperedgeScope`, and `EndpointScope`. GraphML endpoint
elements themselves do not accept data children. An untyped raw `Key` may hold
XML defaults. `DataValue` is either `ScalarValue(Scalar)` or
`XmlPayload(Array[XmlValue])`; `Datum::new(key, scalar, id?)` is the scalar helper.

Key IDs, not `attr.name` strings, identify data. Attribute names can be repeated
across declarations. One owner cannot carry duplicate data entries for a key.
Explicit empty strings and omitted values with defaults remain distinct.
GraphML identifier/name fields follow XML NMTOKEN rules; a name may start with a
digit but cannot contain spaces. XML element/attribute local names and namespace
prefixes instead follow NCName rules, including a valid first character and no
colon inside the local name. GraphML `desc` is plain text: child elements and
attributes, including `xml:lang`, are rejected rather than silently dropped.

## XML payloads and namespace context

`XmlElementValue` holds `namespace_uri`, local `name`, optional element `prefix`,
in-scope `namespaces`, expanded-name `attributes`, and ordered `content`.
`NamespaceBinding` holds an optional `prefix` and its `namespace_uri`: `None`
means the default namespace, and an empty URI resets that default. An
unnamespaced element uses `namespace_uri=None`, not `Some("")`. A prefixed
element's binding must agree with its expanded namespace; conflicting bindings,
duplicate prefix declarations, and reserved `xml`/`xmlns` misuse raise errors.

Parsed payload elements retain inherited namespace bindings, even if those
prefixes appear only in opaque text or attribute values such as
`xsi:type="p:Rectangle"`. Serialization reuses or safely generates prefixes
without overwriting saved bindings, and preserves an empty default namespace
where it matters to an unprefixed `xsi:type`. XML attribute prefix spellings may
change; their expanded names and values do not. These records are not an XML
Schema type system: QName-looking values are not resolved, rewritten, or checked
against an application schema.

`Key.default_extra` retains attributes on the `default` wrapper;
`Key.default_namespaces` retains that wrapper's in-scope bindings, including
bindings needed by text-only defaults or wrapper attributes. `Key.extra`
instead describes attributes on the `key` element. `Key::new` initializes both
default-metadata arrays empty; raw record construction or record updates can
set them when required. `keys()` deep-copies these arrays. `Key.namespaces` and
the structural records' `namespaces` preserve the context of their own extra
attributes. `Datum.namespaces` also preserves opaque text-value context;
`Document::namespace_bindings()` returns the detached root context.
The writer may select a prefixed GraphML element to keep a saved empty or
foreign default namespace intact. Context preservation does not interpret or
validate an application-defined QName or vendor schema.

## Construction and ownership

The public structural records are `Graph`, `Node`, `Edge`, `Port`, `Hyperedge`,
`Endpoint`, and `Locator`. Constructors such as `Graph::new(direction, id?)`,
`Node::new(id)`, `Edge::new(source, target, id?)`, and `Port::new(name)` make
building records convenient. Their arrays are mutable during construction.
`Document::new(keys, graphs, data?, description?, extra?, namespaces?, limits?)` validates the
complete candidate before creating an owned document.

Documents do not expose mutable internal arrays: `keys()`, `graphs()`, `data()`,
`extra_attributes()`, `namespace_bindings()`, and addressed record access return detached values.
`description()`, `key_count()`, and `graph_count()` inspect document metadata.
Changing construction inputs, getters' returned arrays, or a builder after
`finish()` does not change an existing document.

For large flat graphs, `FlatBuilder::new(keys, direction, graph_id?, limits?)`
supports batch construction. `add_node`, `add_edge`, and `set_graph_data` check
local inputs before mutation. Edge endpoints may be forward references until
`finish()` performs whole-document validation. `node_count()` and
`edge_count()` inspect construction progress. Repeated `finish()` is permitted.
This avoids revalidating and copying the whole document after every insertion.

## Addresses and ID indexes

Graph IDs are document-global. Node, binary-edge, hyperedge, and endpoint IDs
are scoped to a top-level graph's descendant subtree; separate top-level
graphs may reuse those IDs. Edge/endpoint references must stay within the
containing graph's subtree. Port names must satisfy the GraphML descendant-port
uniqueness rule, including nested graphs owned by a node.

`GraphAddress::root(index)` addresses a top-level graph.
`.child(NodeGraph(index))`, `.child(EdgeGraph(index))`, or
`.child(HyperedgeGraph(index))` addresses a graph nested in an owning element.
These are ordinal addresses: reconstruct the index if a transformation changes
element ordering. `ElementAddress` combines a graph address and element index.

`GraphIndex::new(document)` provides ID lookups through `graph_address`,
`node_address`, `edge_address`, `hyperedge_address`, `node`, and `edge`.
Node/edge lookups take the top-level root index to disambiguate reused IDs.
`incident_edges(root, node)` and `incident_hyperedges(root, node)` return
addresses. A self-loop appears once in an incident list; this is not a graph
degree computation. `Document::graph_at`, `node_at`, and `edge_at` resolve
addresses with bounds checks and return detached records.

## Attributes and defaults

Construct `Attributes::new(document, scope, data, limits?=Limits::default())`
for a particular owner. Besides key/scope/type checks, it uses bounded XML
serialization/reparsing to validate and detach caller-supplied data, including
extension XML, characters, namespace contexts, and cyclic/deep payloads.
Construction failure leaves the input document unchanged.
`get(key, use_default?=true)` returns `DataValue?`; `scalar(...)` returns
`Scalar?` and rejects XML payloads. `contains_explicit(key)` distinguishes
stored data from a default. `key_by_name(name)` raises on ambiguous names rather
than picking an arbitrary declaration. `resolved()` returns applicable values
in declaration order, retaining explicit data metadata and adding defaults only
where data is absent. A synthesized default `Datum` carries its default's
namespace context, but does not copy attributes from the differently typed
`default` wrapper onto a `data` element. `get()` returns the value alone; use
`resolved()` or the document records when container metadata is needed.

## Flat graph adapters

`Document::flat_graph(address)` selects a single binary graph view. It rejects
nested graphs, ports, hyperedges, and unresolved locators instead of discarding
them. `FlatGraph::graph()` returns its detached graph; `to_document(limits?)`
creates a one-graph document. Document-level metadata is outside this selected
graph view.

`node_rows(use_defaults?=true)` and `edge_rows(use_defaults?=true)` project scalar
attributes into maps keyed by declaration IDs. They reject XML payloads, which
cannot be silently converted to scalar cells. Descriptions and XML metadata
remain in `graph()`, not in row tables. `indexed_edges()` supplies positional
endpoints, preserving binary edge multiplicity and effective direction, for an
application's existing algorithm library.

`from_rows(keys, nodes, edges, edge_default?, graph_id?, limits?)` builds a
validated flat document from `NodeRow` and `EdgeRow` records. Types/scopes come
from explicit declarations; this function does not infer numeric coercions or
merge parallel edges. It checks structural ceilings before building internal
copies, ranks declarations once, and orders only the actual keys in each row.
Table projection prefilters applicable default declarations once per call.

## Immutable transformations

Each transformation returns a new validated document and leaves its input
unchanged. `rename_key(old, new)` rewrites declarations and every data reference;
`replace_key(key)` retains its ID and revalidates existing values;
`remove_key(id)` fails if stored data would become undefined.

`rename_node(root, old, new)` updates binary-edge and hyperedge references in
one root scope. `rename_port(root, node_id, old, new)` updates references to the
owning node's hierarchical port. `replace_node(address, node)` and
`replace_edge(address, edge)` never implicitly delete dangling references.

`replace_graph(address, graph)` revalidates ancestor references and global IDs.
`append_graph(graph)` preserves existing root ordinals.
`select_graphs(roots)` retains the requested root order, shared key declarations,
and document metadata; duplicate selections are rejected.

`merge(other, prefix)` appends independently scoped imported graphs, prefixes
imported key IDs and document-global graph IDs, and returns `MergeResult` with
`document`, `imported_roots`, `key_mapping`, and `graph_mapping`. Node IDs need no
prefix because the appended roots retain separate scopes. Colliding prefixed
IDs, conflicting root extension attributes, or different nonempty root
descriptions raise errors rather than losing information. When both roots carry
opaque extra-attribute values, conflicting prefix/default-namespace contexts
also raise an error, even if the values do not look like prefixed QNames:
their application types cannot be inferred safely. When only one root carries
such values, its context takes priority; appended graphs retain their own
contexts. References embedded
in opaque XML or locator text are not interpreted or rewritten.

## Induced subgraphs

`FlatGraph::induced_subgraph(node_ids, limits?) -> Document` extracts a node-induced
copy: exactly the selected vertices and all binary edges whose two endpoints are
selected. It retains source node/edge order, not selection order, including
isolates, self-loops, parallel edges, and per-edge direction overrides. Empty
selection produces a valid empty graph. Unknown or repeated selections raise
`InvalidGraph` at `subgraph.nodes`. No node/edge identifiers are renumbered.

Keys, defaults (including unused declarations), graph description/data, authored
node/edge data and XML attributes/namespace contexts are retained. All
unqualified `parse.*` graph/node hints are removed because counts, degrees,
canonical ordinal IDs and ordering assumptions can become stale. Namespaced
extension attributes are retained even with similar local names. The original
document is unchanged; the returned document is fully validated and detached.
Document-root metadata is outside this `FlatGraph` selection, just as with
`to_document()`. Embedded application references in XML/extra attributes are
opaque: they are not rewritten or guaranteed to refer to retained nodes; callers
with such schemas must validate the extracted result themselves.

The structural selection costs expected `O(V+E+Q)` time for `Q` selected IDs and
`O(Q+V'+E')` working space, using hash membership instead of testing every ID
against every vertex/edge. This is followed by the normal whole-result
validation, serialization and ownership reparse, whose cost includes metadata,
keys and namespace contexts. `Limits` applies to the resulting document, not as
a smaller new limit on the source; node/edge ceilings are also checked before
growing selected arrays. Unsupported hierarchy/ports/hyperedges/locators are
already rejected by `Document::flat_graph`, not silently discarded here.

## CSR adjacency adapter

`FlatGraph::to_csr(orientation?=Outgoing, max_arcs?=2000000) -> CsrAdjacency`
produces an immutable compressed sparse row topology adapter. Node ordinals
follow `FlatGraph::graph().nodes`; edge ordinals follow its `.edges`. It does not
run graph algorithms, perform numerical aggregation, or infer weight types.

- `node_count()`, `arc_count()`: stored vertices and adjacency entries.
- `node_index(id)`: expected constant-time lookup, `None` for absent IDs.
- `node_ids()`, `indptr()`, `indices()`, `edge_indices()`, `reversed()`: detached
  arrays. Row `i` occupies `[indptr[i], indptr[i+1])`; `indices` are target node
  ordinals, and each `edge_indices` entry maps to the original edge record.
- `row(i)`: a detached array of `CsrEntry {target, edge_index, reversed}` in
  `O(degree(i))` time. Invalid/negative indices raise `InvalidGraph` at `csr.row`.

Outgoing directed edges emit source-to-target; Incoming emits target-to-source
and sets `reversed=true`, including directed self-loops. Undirected non-loops
emit one arc per endpoint (forward then reversed); undirected self-loops emit
one forward arc in either mode. This is adjacency storage, **not** an incidence
degree count that counts undirected loops twice. Each row follows original edge
order. Parallel entries are retained and column indices need not be sorted;
these are valid noncanonical CSR arrays, not a canonical sparse matrix.

Read scalar/Int64/default/XML edge values from the original flat graph or its
typed rows using edge ordinals. A numerical consumer must explicitly choose
weight conversion and parallel-edge aggregation rules; do not blindly treat
edge ordinals as numerical weights. `row()`/array getters cannot modify the
stored adapter. Topology export does not copy XML payloads or coerce values.

Construction uses degree counting, prefix sums and stable scatter: expected
`O(V+E)` time and `O(V+A)` space (`A<=2E`), versus scanning all edges per row
(`O(V*E)`) or allocating a dense `V*V` matrix. The arc count is preflighted
before any arc buffers are allocated; a negative budget is `InvalidGraph` at
`csr.max_arcs`, exceeding it is `LimitExceeded(resource="csr.arcs")`. Explicit
subtraction guards prevent overflow during counting, and `V+1` is checked.
Budgets are not host-process memory guarantees. Hashing costs depend on ID
lengths. Full array getters copy `O(V)` or `O(A)` values; prefer `row()` when only
one adjacency list is needed.

CSR convention reference: [SciPy CSR representation](https://docs.scipy.org/doc/scipy/reference/generated/scipy.sparse.csr_matrix.html).
Induced-selection definition: [NetworkX MultiDiGraph.subgraph](https://networkx.org/documentation/stable/reference/classes/generated/networkx.MultiDiGraph.subgraph.html).
These are design/format references, not copied implementations or runtime
dependencies. In contrast to NetworkX views, MoonGraphML returns an owned copy
and deliberately rejects unknown/duplicate selection IDs.

## Equivalence, statistics, and parse hints

`Document::equivalent(other)` compares the supported information model, ignoring
key/data declaration order, XML attribute order and element-prefix spelling,
adjacent text-node segmentation, and graph `parse.order`. It conservatively
compares namespace bindings for prefixes occurring in opaque payload and container
text/attribute values and the default binding for unprefixed `xsi:type` values.
Key-default wrapper attributes/context and all structural container contexts
are included. Changing such a QName
binding is not reported equivalent merely because the literal value is unchanged.
The library does not infer QName semantics for every unprefixed application
value or validate application schemas. Node, edge, port, endpoint, and graph
ordinals remain significant for stable addressing. Explicit data and omitted
defaults remain distinct. This is neither graph isomorphism nor XML C14N.

`statistics()` counts stored structure, including nested graphs, ports,
endpoints, and data entries, and flags mixed direction, parallel edges,
self-loops, locators, and XML payloads. It does not expand hyperedges or fetch
external graphs.

`Graph::parse_info()` and `Node::degree_hints()` parse advisory `parse.*`
metadata. `CountHint` stores an arbitrary-length nonnegative decimal count;
`to_int64()` returns `None` if it does not fit. Lexical validity does not prove
that a hint agrees with structure. `ParseInfo::check_flat_counts(graph)` checks
flat node/edge counts and canonical ID sequences explicitly. It does not
invent nested-graph counting rules. Serialization groups nodes first and
updates an existing `parse.order` hint to `nodesfirst`; other hints are retained
and can become stale after edits.

## Resource budgets and cost

`Limits::default()` sets the following configurable ceilings:

| Resource | Default |
| --- | ---: |
| UTF-8 input bytes | 32 MiB |
| XML depth | 64 (configuration maximum 256) |
| XML event budget (`xml_elements` field) | 1,000,000 |
| Attributes and namespace declarations per element | 64 |
| Text/attribute budget (`text_bytes`) | 4 MiB |
| Key declarations | 4,096 |
| Graphs | 4,096 |
| Nodes | 200,000 |
| Binary edges and hyperedges combined | 1,000,000 |
| Ports | 1,000,000 |
| Hyperedge endpoints | 1,000,000 |
| UTF-8 output bytes | 64 MiB |

Limits are ceilings, not guaranteed supported dataset sizes or process-memory
caps. The XML input tree and typed model are buffered. `xml_elements` counts
parser events, including starts, ends, and text, rather than just graph nodes.
Text budgets include accumulated direct text in an element, not only an
individual parser event. Choose lower input/depth/output limits for untrusted
sources and apply process-level memory/time limits in the host application.

For a flat graph, XML parsing/serialization and structural validation scale
with input/output text and stored data. Hierarchical validation collects each
graph's subtree, so deeply nested documents can revisit descendants up to their
bounded depth; it is not uniformly linear in graph size. ID-index construction
and statistics use structural scans and hash maps. Immutable transformations
and `Document::new` revalidate and detach the whole resulting document; use a
batch builder for repeated additions rather than repeated complete rebuilds.
For `R` rows, `K` declarations, `A` authored attributes and `M` applicable
defaults, table projection costs `O(K + A + R*M)`; opting out of defaults skips
the declaration scan. Sparse row construction costs
`O(K + sum(A_i*log(A_i+1)))` before whole-document validation. Large numbers of
materialized defaults inherently produce large outputs.

Namespace contexts use small ordered arrays. With `C` in-scope bindings, repeated
prefix lookups can make an element's namespace preparation `O(C^2)`;
namespace-heavy documents are not covered by ordinary flat-graph throughput
figures. Detached getters copy contexts as well as graph structure. Depth and
declaration budgets bound this work, but are not a host CPU/time quota.
Serialization enforces output bytes/depth, per-element attribute/namespace
counts, and text/attribute budgets; `input_bytes` and XML parser-event budgets
apply when reading, including ownership-boundary reparsing.
No hardware-independent latency or throughput guarantee is made.
