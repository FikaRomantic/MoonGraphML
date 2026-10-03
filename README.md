# MoonGraphML

MoonBit-native GraphML graph-data interchange library, under development.

The core handles graph structure, typed attributes, and validated import/export.
It is designed for dependency-analysis tools, network/asset topology, and scientific
graph datasets. Graph algorithms and visual layout remain with the caller's chosen libraries.

The implementation is original MIT code. XML syntax and namespaces use
[Milky2018/xml](https://github.com/moonbit-community/xml-mbt), Apache-2.0.
NetworkX and igraph serve as independent interoperability oracles; their source
is not copied into this project.

Development: `moon check --target all`, `moon test --target all`.
Local proposals and review reports live in `.local/`, excluded from Git and releases.
