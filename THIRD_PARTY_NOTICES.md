# Third-party notices

The original MoonGraphML source, tests, examples, and documentation are released
under the [MIT license](LICENSE). This project is an original implementation of
the public GraphML information model; it is not a source-code port of NetworkX
or igraph.

## MoonBit dependencies

| Dependency | Version | License | Use |
| --- | --- | --- | --- |
| [Milky2018/xml](https://github.com/moonbit-community/xml-mbt) | 0.5.0 | Apache-2.0 | XML syntax and expanded-name namespace parsing |
| [moonbitlang/x](https://github.com/moonbitlang/x) | 0.4.49 | Apache-2.0 | CLI filesystem and process helpers |

Dependencies are declared in `moon.mod` and downloaded by MoonBit's package
manager. Their source/license metadata is maintained upstream; no vendored
dependency implementation is committed here. The MoonBit core packages used by
the toolchain retain their upstream licensing. Redistributions that bundle
dependency source or compiled code must retain the applicable upstream licenses
and required notices; this MIT license does not replace those licenses.
The Apache license is available from the
[Apache Software Foundation](https://www.apache.org/licenses/LICENSE-2.0).

## Development-only independent tools

| Tool | Version used | License | Use |
| --- | --- | --- | --- |
| [NetworkX](https://github.com/networkx/networkx) | 3.6.1 | BSD-3-Clause | Independent GraphML differential oracle |
| [python-igraph / igraph](https://github.com/igraph/python-igraph) | 1.0.0 | GPL-2.0-or-later | Independent GraphML differential oracle |
| [lxml](https://lxml.de/copyright.html) | 6.1.3 | BSD-3-Clause for lxml itself | Python reference XML support and schema-check tooling |
| [xmlschema](https://github.com/sissaschool/xmlschema) | 4.3.2 | MIT | Independent XML Schema oracle |
| [elementpath](https://github.com/sissaschool/elementpath) | 5.1.4 | MIT | XPath support required by xmlschema |
| [texttable](https://github.com/foutaise/texttable) | 1.7.0 | MIT | python-igraph's table-formatting dependency |

These separately installed tools are not runtime dependencies of the MoonBit
library and are not redistributed in this repository or Mooncakes package.
Their implementations have not been copied into MoonGraphML. Python binary
distributions can include additional components (for example libxml2/libxslt in
lxml wheels); those components retain their own upstream licenses.
Installed distribution metadata and license files identify xmlschema and
elementpath as MIT-licensed SISSA projects, and texttable as MIT-licensed work
by Gerome Fournier. These tools' licenses are independent of the original
MoonGraphML source license.

The Python suite generates its own test graph data. Local reference-tool
installations, downloaded schemas, generated fixtures, and run results live in
ignored `.local/` and are not vendored source. GraphML schemas/specification are
consulted as normative references; they are not relicensed as project source.

## Specification and workflow references

The model follows the public
[GraphML specification](http://graphml.graphdrawing.org/specification.html).
The CI installation and lint conventions follow the MoonBit community's
[official check workflow template](https://github.com/moonbit-community/.github/blob/main/workflow-templates/check.yml),
with additional build, warning, and executable-example gates.
