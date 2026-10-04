"""Independent GraphML standard, advanced-structure and rejection corpus.

The unmodified official GraphML 1.0 XSDs are downloaded only into .local and
resolved offline by exact URL. Both original and MoonBit-emitted documents are
validated. XML extension payloads use a separate, original, *strict* redefine
schema with one explicitly declared payload vocabulary, never xs:any/lax.
XSD does not type GraphML data text from attr.type, enforce key scopes, or place
resource bounds; those cases deliberately test MoonGraphML's stronger contract.
No external standard/schema bytes or generated reports are committed.
"""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.request
from xml.sax.saxutils import escape, quoteattr

ROOT = Path(__file__).resolve().parents[1]
ORACLES = ROOT / ".local" / "oracles"
if ORACLES.exists():
    sys.path.insert(0, str(ORACLES))
from lxml import etree
import xmlschema

GML = "http://graphml.graphdrawing.org/xmlns"
XLINK = "http://www.w3.org/1999/xlink"
XSI = "http://www.w3.org/2001/XMLSchema-instance"
SCHEMA_BASE = "http://graphml.graphdrawing.org/xmlns/1.0/"
SCHEMA_NAMES = ("graphml.xsd", "graphml-structure.xsd", "xlink.xsd")
SCHEMA_SHA256 = {
    "graphml.xsd": "c5d04fb93d579712aa375f3ace67fe9243d6aaa9b039576516722af2d9c5af52",
    "graphml-structure.xsd": "7809123855d2ef634dea2b678055b6230607efb9addde55a06c4afd67075a04b",
    "xlink.xsd": "4f76a2f3c026979b733f92d3f85c815723848b72731a72ef40a1709959b698ed",
}
EXTENSION_NAMESPACE = "urn:moongraphml:original-test-payload"


@dataclass(frozen=True)
class Case:
    name: str
    category: str
    xml: str
    diagnostic: str = ""
    schema_profile: str = "official"
    schema_must_reject: bool = False


def document(content: str, keys: str = "", description: str = "") -> str:
    desc = f"<desc>{escape(description)}</desc>" if description else ""
    return f'<graphml xmlns="{GML}" xmlns:xlink="{XLINK}">{desc}{keys}{content}</graphml>'


def graph(content: str, *, gid: str = "g", direction: str = "directed", hints: str = "") -> str:
    return f'<graph id={quoteattr(gid)} edgedefault={quoteattr(direction)} {hints}>{content}</graph>'


def scalar_key(key: str, kind: str, scope: str = "all", default: str | None = None) -> str:
    value = f"<default>{escape(default)}</default>" if default is not None else ""
    return f'<key id={quoteattr(key)} for={quoteattr(scope)} attr.name={quoteattr(key)} attr.type={quoteattr(kind)}>{value}</key>'


def positive_cases(count: int):
    """Deterministic original corpus; each scenario varies values and graph size."""
    for seed in range(count):
        kind = seed % 12
        variant = seed // 12
        n = 2 + variant % 7
        nodes = "".join(f'<node id="n{i}"/>' for i in range(n))
        edges = "".join(f'<edge id="e{i}" source="n{i % n}" target="n{(i + 1) % n}"/>' for i in range(n + variant % 3))
        keys = ""
        if kind == 0:
            category = "mixed_parallel_self_loop"
            body = graph(nodes + edges + '<edge id="loop" source="n0" target="n0" directed="false"/>'
                         + '<edge id="parallel" source="n0" target="n1" directed="0"/>')
        elif kind == 1:
            category = "nested_node_cross_level_reference"
            nested = graph('<node id="inner0"/><node id="inner1"/>'
                           '<edge id="inneredge" source="inner0" target="inner1"/>', gid=f"inner{variant}", direction="undirected")
            body = graph(f'<node id="parent">{nested}</node><node id="peer"/>'
                         '<edge id="cross" source="inner0" target="peer"/>')
        elif kind == 2:
            category = "nested_edge_graph"
            nested = graph('<node id="detail0"/><node id="detail1"/>'
                           '<edge id="detail_edge" source="detail0" target="detail1"/>', gid=f"detail{variant}")
            body = graph(nodes + f'<edge id="carrier" source="n0" target="n1">{nested}</edge>')
        elif kind == 3:
            category = "nested_hyperedge_graph"
            nested = graph('<node id="detail0"/><node id="detail1"/>', gid=f"detail{variant}")
            body = graph(nodes + f'<hyperedge id="h"><endpoint node="n0" type="in"/>'
                         f'<endpoint node="n1" type="out"/>{nested}</hyperedge>')
        elif kind == 4:
            category = "hierarchical_ports_and_data"
            keys = scalar_key("bandwidth", "long", "port", str(variant + 1))
            body = graph('<node id="n0"><port name="physical"><desc>设备端口</desc>'
                         '<port name="logical"><data key="bandwidth">9007199254740993</data></port>'
                         '</port></node><node id="n1"><port name="rx"/></node>'
                         '<edge source="n0" target="n1" sourceport="logical" targetport="rx"/>')
        elif kind == 5:
            category = "hyperedge_endpoint_directions_and_ports"
            keys = scalar_key("role", "string", "hyperedge", "broadcast")
            body = graph('<node id="n0"><port name="tx"/></node><node id="n1"><port name="rx"/></node>'
                         '<hyperedge id="h"><desc>共享关联</desc><data key="role">group</data>'
                         '<endpoint id="in" node="n0" port="tx" type="in"><desc>输入</desc></endpoint>'
                         '<endpoint id="out" node="n1" port="rx" type="out"/>'
                         '<endpoint id="undirected" node="n0" type="undir"/></hyperedge>')
        elif kind == 6:
            category = "all_key_scopes_defaults_and_doc_data"
            keys = (scalar_key("label", "string", "all", f"缺省 {variant}")
                    + scalar_key("root", "boolean", "graphml", "true")
                    + scalar_key("node_count", "int", "node", str(variant))
                    + '<key id="unused_endpoint" for="endpoint" attr.type="string"/>')
            body = '<data key="root">1</data>' + graph('<data key="label">graph</data>'
                    '<node id="n0"><data key="node_count">-2147483648</data></node><node id="n1"/>'
                    '<edge source="n0" target="n1"><data key="label">edge</data></edge>')
        elif kind == 7:
            category = "unicode_whitespace_entities_cdata"
            keys = scalar_key("标签", "string", "node", "  默认\t值\n😀  ")
            text = f"  中文😀序号{variant}\n\t<&> \r end  "
            encoded = escape(text).replace("\r", "&#13;")
            body = graph(f'<node id="节点{variant}"><desc>説明 &amp; &lt; <![CDATA[<!DOCTYPE is text>]]></desc>'
                         f'<data key="标签">{encoded}</data></node>', gid=f"图{variant}")
        elif kind == 8:
            category = "scalar_boundaries_and_special_floats"
            values = ("true", "-2147483648", "9223372036854775807", "INF", "-INF", "NaN", "-0.0")
            types = ("boolean", "int", "long", "float", "double", "double", "double")
            keys = "".join(scalar_key(f"k{i}", typ, "node", value) for i, (typ, value) in enumerate(zip(types, values)))
            data = "".join(f'<data key="k{i}">{value}</data>' for i, value in enumerate(values))
            body = graph(f'<node id="n{variant}">{data}</node>')
        elif kind == 9:
            category = "locator_metadata_only"
            # These URLs deliberately cannot resolve locally. Passing proves that
            # ordinary conversion did not need or fetch their contents.
            body = graph(f'<desc>外部元数据 {variant}</desc><locator xlink:href="http://127.0.0.1:1/not-fetched-{variant}" xlink:type="simple"/>', gid="external")
            body += graph(f'<node id="n{variant}"><desc>节点元数据</desc>'
                          '<locator xlink:href="file:///definitely-not-a-real-graphml.graphml"/></node>', gid="inline")
        elif kind == 10:
            category = "parse_advisory_arbitrary_precision_hints"
            huge = str(10 ** (20 + variant % 20) + variant)
            body = graph(f'<node id="n0" parse.indegree="+000{variant}" parse.outdegree="{huge}"/>'
                         '<node id="n1"/><edge id="e0" source="n0" target="n1"/>',
                         hints=f'parse.nodes="{huge}" parse.edges="0001" parse.maxindegree="0" '
                         'parse.maxoutdegree="+2" parse.nodeids="free" parse.edgeids="free" parse.order="free"')
        else:
            category = "namespace_prefixes_and_separate_top_level_scopes"
            xml = f'<g:graphml xmlns:g="{GML}"><g:graph id="g0" edgedefault="directed">'
            xml += f'<g:node id="n{variant}"/></g:graph><g:graph id="g1" edgedefault="undirected">'
            xml += f'<g:node id="n{variant}"/></g:graph></g:graphml>'
            yield Case(f"positive_{seed:04d}", category, xml)
            continue
        yield Case(f"positive_{seed:04d}", category, document(body, keys, f"Original standards corpus {seed}"))


def extension_cases(count: int):
    for seed in range(count):
        payload = f'<e:payload xmlns:e="{EXTENSION_NAMESPACE}" version="{seed}"><e:unit scale="{seed + 1}">'
        payload += escape(f"值 {seed} 😀<&>\n") + '</e:unit></e:payload>'
        keys = '<key id="structured" for="node"><default>' + payload + '</default></key>'
        body = graph('<node id="n0"><data key="structured">' + payload + '</data></node>')
        yield Case(f"extension_{seed:04d}", "strict_original_xml_extension", document(body, keys), schema_profile="extension")


def qname_context_cases(structure_schema: Path):
    """Legal xsi:type names verified against actual official element declarations.

    These are a separate group: xmlschema 4.3.2 can recurse indefinitely while
    resolving the standard's redefined type graph for xsi:type. The unchanged
    official XSD is therefore evaluated by lxml for each input and output, with
    a reverse guard that must reject the same XML after removing its QName
    binding. Neither engine error is counted as a successful schema rejection.
    """
    inventory = {
        "graphml": "graphml.type", "graph": "graph.type", "node": "node.type",
        "edge": "edge.type", "port": "port.type", "hyperedge": "hyperedge.type",
        "endpoint": "endpoint.type", "key": "key.type", "locator": "locator.type",
        "data": "data.type", "default": "default.type",
    }
    official = etree.parse(str(structure_schema), etree.XMLParser(no_network=True, resolve_entities=False))
    namespaces = {"xs": "http://www.w3.org/2001/XMLSchema"}
    for element, expected_type in inventory.items():
        actual = official.xpath("/xs:schema/xs:element[@name=$element]/@type", namespaces=namespaces, element=element)
        assert actual == [expected_type], f"fixture type not proven by official XSD: {element}: {actual}"
        assert official.xpath("boolean(/xs:schema/xs:complexType[@name=$kind])", namespaces=namespaces, kind=expected_type), (
            f"official complex type declaration missing: {expected_type}")

    for element, typename in inventory.items():
        attribute = f'xsi:type="g:{typename}"'
        root_attribute = attribute if element == "graphml" else ""
        graph_attribute = attribute if element == "graph" else ""
        keys = ""
        if element in {"node", "port", "edge", "hyperedge", "endpoint", "data"}:
            node_attribute = attribute if element == "node" else ""
            node_body = f'<port name="physical" {attribute}/>' if element == "port" else ""
            if element == "data":
                keys = scalar_key("label", "string", "node")
                node_body = f'<data key="label" {attribute}>标签 😀&amp;&lt;</data>'
            content = f'<node id="n0" {node_attribute}>{node_body}</node><node id="n1"/>'
            if element == "edge":
                content += f'<edge id="e" source="n0" target="n1" {attribute}/>'
            if element == "hyperedge":
                content += f'<hyperedge id="h" {attribute}><endpoint node="n0"/></hyperedge>'
            if element == "endpoint":
                content += f'<hyperedge id="h"><endpoint node="n0" {attribute}/></hyperedge>'
        elif element == "locator":
            content = f'<locator xlink:href="http://127.0.0.1:1/not-fetched-qname" {attribute}/>'
        else:
            content = ""
        if element == "key":
            keys = f'<key id="label" for="node" attr.type="string" {attribute}/>'
        if element == "default":
            keys = f'<key id="label" for="node" attr.type="string"><default {attribute}>默认值</default></key>'
        xml = (f'<graphml xmlns="{GML}" xmlns:g="{GML}" xmlns:xsi="{XSI}" xmlns:xlink="{XLINK}" {root_attribute}>'
               + keys + f'<graph edgedefault="directed" {graph_attribute}>' + content + '</graph></graphml>')
        yield Case(f"qname_{element}", f"xsi_type_{element}", xml)


def expanded_type_signature(xml: str):
    """Independent semantic check for the expanded QName *attribute value*."""
    root = etree.fromstring(xml.encode("utf-8"), etree.XMLParser(no_network=True, resolve_entities=False))
    result = []
    for element in root.iter():
        value = element.get(f"{{{XSI}}}type")
        if value is None:
            continue
        assert value.count(":") == 1, f"fixture/output type must be explicitly prefixed: {value}"
        prefix, local_name = value.split(":")
        namespace = element.nsmap.get(prefix)
        assert namespace == GML, f"type QName lost/rebound its official namespace: {value}: {namespace}"
        result.append((element.tag, namespace, local_name))
    assert result, "QName test unexpectedly lacked xsi:type"
    return tuple(sorted(result))


def remove_qname_binding(xml: str):
    """Remove only the g binding, preserving all element/attribute XML names."""
    pattern = r'\s+xmlns:g\s*=\s*(?:"' + re.escape(GML) + r'"|\'' + re.escape(GML) + r'\')'
    stripped, count = re.subn(pattern, "", xml)
    assert count > 0, "QName reverse guard did not remove a real declaration"
    return stripped


def negative_cases(variants: int):
    for seed in range(variants):
        bad = f"missing{seed}"
        # Each template is a distinct structural, lexical, semantic or security
        # failure; variants vary actual IDs/payloads rather than repeating a file.
        cases = [
            ("missing_source_reference", document(graph(f'<node id="n0"/><edge source="{bad}" target="n0"/>')), r"edge\.source:.*outside", True),
            ("missing_target_reference", document(graph(f'<node id="n0"/><edge source="n0" target="{bad}"/>')), r"edge\.target:.*outside", True),
            ("missing_endpoint_reference", document(graph(f'<node id="n0"/><hyperedge><endpoint node="{bad}"/></hyperedge>')), r"endpoint\.node:.*outside", True),
            ("duplicate_node_id", document(graph(f'<node id="n{seed}"/><node id="n{seed}"/>')), r"node\.id:.*duplicate", True),
            ("duplicate_graph_id", document(graph('', gid=f"g{seed}") + graph('', gid=f"g{seed}")), r"graph\.id:.*duplicate", True),
            ("duplicate_edge_id", document(graph(f'<node id="n0"/><edge id="e{seed}" source="n0" target="n0"/><edge id="e{seed}" source="n0" target="n0"/>')), r"edge\.id:.*duplicate", True),
            ("duplicate_hyperedge_id", document(graph(f'<hyperedge id="h{seed}"/><hyperedge id="h{seed}"/>')), r"hyperedge\.id:.*duplicate", True),
            ("duplicate_endpoint_id", document(graph(f'<node id="n0"/><hyperedge><endpoint id="p{seed}" node="n0"/><endpoint id="p{seed}" node="n0"/></hyperedge>')), r"endpoint\.id:.*duplicate", True),
            ("duplicate_recursive_port_name", document(graph(f'<node id="n0"><port name="p{seed}"><port name="p{seed}"/></port></node>')), r"port\.name:.*duplicate", True),
            ("duplicate_nested_node_port_name", document(graph(f'<node id="n0"><port name="p{seed}"/>'+graph(f'<node id="inner"><port name="p{seed}"/></node>', gid="inner")+'</node>')), r"port\.name:.*duplicate", True),
            ("missing_source_port", document(graph(f'<node id="n0"/><edge source="n0" target="n0" sourceport="{bad}"/>')), r"port\.reference:.*missing", False),
            ("missing_endpoint_port", document(graph(f'<node id="n0"/><hyperedge><endpoint node="n0" port="{bad}"/></hyperedge>')), r"port\.reference:.*missing", False),
            ("nested_graph_ancestor_reference", document(graph('<node id="ancestor"/><node id="parent">'+graph(f'<node id="n{seed}"/><edge source="ancestor" target="n{seed}"/>', gid="inner")+'</node>')), r"edge\.source:.*outside", True),
            ("parent_cannot_use_nested_node_port", document(graph('<node id="parent">'+graph(f'<node id="child"><port name="p{seed}"/></node>', gid="inner")+f'</node><edge source="parent" target="parent" sourceport="p{seed}"/>')), r"port\.reference:.*missing", False),
            ("duplicate_key_id", document(graph(''), scalar_key(f"k{seed}", "string") + scalar_key(f"k{seed}", "int")), r"key\.id:.*duplicate", True),
            ("undefined_data_key", document(graph(f'<node id="n0"><data key="{bad}">x</data></node>')), r"data\.key:.*undefined", True),
            ("duplicate_data_key", document(graph(f'<node id="n0"><data key="k">{seed}</data><data key="k">{seed + 1}</data></node>'), scalar_key("k", "int")), r"node:.*duplicate data", True),
            ("wrong_node_key_scope", document(graph(f'<node id="n0"><data key="k">{seed}</data></node>'), scalar_key("k", "int", "edge")), r"node:.*scope", False),
            ("wrong_graph_key_scope", document(graph(f'<data key="k">{seed}</data>'), scalar_key("k", "int", "node")), r"graph:.*scope", False),
            ("wrong_doc_key_scope", document(f'<data key="k">{seed}</data>', scalar_key("k", "int", "graph")), r"graphml:.*scope", False),
            ("boolean_lexical_case", document(graph('<node id="n0"><data key="k">True</data></node>'), scalar_key("k", "boolean")), r"data\.boolean:", False),
            ("integer_overflow", document(graph(f'<node id="n0"><data key="k">{2147483648 + seed}</data></node>'), scalar_key("k", "int")), r"data\.int:.*overflow", False),
            ("long_overflow", document(graph(f'<node id="n0"><data key="k">{9223372036854775808 + seed}</data></node>'), scalar_key("k", "long")), r"data\.long:.*overflow", False),
            ("integer_non_decimal", document(graph(f'<node id="n0"><data key="k">0x{seed + 10:x}</data></node>'), scalar_key("k", "int")), r"data\.int:.*decimal", False),
            ("float_overflow", document(graph(f'<node id="n0"><data key="k">{4 + seed}E38</data></node>'), scalar_key("k", "float")), r"data\.float:.*overflow", False),
            ("double_overflow", document(graph(f'<node id="n0"><data key="k">1E{400 + seed}</data></node>'), scalar_key("k", "double")), r"data\.double:.*overflow", False),
            ("float_lexical_lowercase_inf", document(graph('<node id="n0"><data key="k">inf</data></node>'), scalar_key("k", "double")), r"data\.double:", False),
            ("typed_scalar_xml_payload", document(graph(f'<node id="n0"><data key="k"><e:payload xmlns:e="urn:test">{seed}</e:payload></data></node>'), scalar_key("k", "int")), r"data:.*extension XML", True),
            ("desc_misplaced", document(graph(f'<node id="n{seed}"/><desc>late</desc>')), r"graph(?:\.desc)?:.*(?:misplaced|first and unique)", True),
            ("key_after_graph", document(graph('') + scalar_key(f"k{seed}", "string")), r"graphml\.key:.*precede", True),
            ("second_nested_graph", document(graph('<node id="n0">'+graph('', gid="inner1")+graph('', gid="inner2")+'</node>')), r"node\.graph:|node:.*nested graph", True),
            ("node_content_after_nested_graph", document(graph('<node id="n0">'+graph('', gid="inner")+f'<port name="p{seed}"/></node>')), r"node\.graph:|node:.*nested graph", True),
            ("endpoint_data_forbidden", document(graph('<node id="n0"/><hyperedge><endpoint node="n0"><data key="k">x</data></endpoint></hyperedge>'), scalar_key("k", "string", "endpoint")), r"endpoint:.*unsupported|desc:.*expected GraphML", True),
            ("endpoint_type_invalid", document(graph(f'<node id="n0"/><hyperedge><endpoint node="n0" type="invalid{seed}"/></hyperedge>')), r"endpoint\.type:", True),
            ("locator_mixed_inline", document(graph(f'<node id="n{seed}"/><locator xlink:href="unused"/>')), r"graph\.locator:|graph:.*(?:exclusive|cannot coexist)", True),
            ("locator_wrong_namespace", document(graph(f'<locator href="file:///not-a-real-{seed}"/>')), r"locator.*href|locator.*namespace", True),
            ("locator_unsupported_link_type", document(graph(f'<locator xlink:href="unused{seed}" xlink:type="extended"/>')), r"locator.*simple", False),
            ("locator_nonempty", document(graph(f'<locator xlink:href="unused{seed}"><desc>not empty</desc></locator>')), r"locator:.*empty", True),
            ("invalid_node_id_token", document(graph(f'<node id="bad id {seed}"/>')), r"node\.id:.*NMTOKEN", True),
            ("invalid_key_scope", document(graph(''), f'<key id="k" for="invalid{seed}"/>'), r"key\.for:", True),
            ("invalid_key_type", document(graph(''), f'<key id="k" attr.type="bytes{seed}"/>'), r"key\.attr\.type:", True),
            ("invalid_graph_direction", document(f'<graph edgedefault="invalid{seed}"/>'), r"graph\.edgedefault:", True),
            ("invalid_edge_boolean", document(graph(f'<node id="n0"/><edge source="n0" target="n0" directed="invalid{seed}"/>')), r"data\.boolean:", True),
            ("invalid_parse_count", document(graph('', hints=f'parse.nodes="-{seed + 1}"')), r"parse\.count:.*negative", True),
            ("invalid_parse_count_lexical", document(graph('', hints=f'parse.edges="{seed}.5"')), r"parse\.count:.*invalid", True),
            ("invalid_parse_order", document(graph('', hints=f'parse.order="invalid{seed}"')), r"parse\.order:", True),
            ("invalid_parse_id_hint", document(graph('', hints=f'parse.nodeids="invalid{seed}"')), r"parse\.nodeids:", True),
            ("unknown_structural_child", document(graph(f'<unsupported{seed}/>')), r"graph:.*unsupported", True),
            ("namespace_spoof", f'<graphml xmlns="urn:fake:{seed}"><graph edgedefault="directed"/></graphml>', r"graphml:.*namespace", True),
            ("namespace_child_spoof", document(graph(f'<node xmlns="urn:fake:{seed}" id="n0"/>')), r"graph:.*namespace", True),
            ("xml_mismatched_tags", f'<graphml xmlns="{GML}"><graph edgedefault="directed"><node id="n{seed}"></graph></graphml>', r"invalid XML:", True),
            ("xml_unknown_entity", document(graph(f'<node id="n{seed}"><desc>&notdefined;</desc></node>')), r"invalid XML:", True),
            ("xml_duplicate_attribute", document(graph(f'<node id="n{seed}" id="duplicate"/>')), r"invalid XML:", True),
            ("xml_unbound_prefix", document(graph(f'<node id="n{seed}" q:name="x"/>')), r"invalid XML:", True),
            ("xml_invalid_codepoint", document(graph(f'<node id="n{seed}"><desc>&#0;</desc></node>')), r"invalid XML:", True),
            ("doctype_entity_expansion", '<!DOCTYPE graphml [<!ENTITY a "boom"><!ENTITY b "&a;&a;&a;&a;">]>'+document(graph(f'<node id="n{seed}"><desc>&b;</desc></node>')), r"xml:.*DOCTYPE", False),
            ("xxe_file_declaration", f'<!DOCTYPE graphml [<!ENTITY attack SYSTEM "file:///definitely-not-real-secret-{seed}">]>'+document(graph('<node id="n0"><desc>&attack;</desc></node>')), r"xml:.*DOCTYPE", False),
            ("xxe_network_declaration", f'<!DOCTYPE graphml SYSTEM "http://127.0.0.1:1/attack-{seed}">'+document(graph('')), r"xml:.*DOCTYPE", False),
            ("depth_budget", document(graph('<node id="n0">'+'<port name="p">'*(65 + seed)+'</port>'*(65 + seed)+'</node>')), r"resource limit exceeded: xml_depth", False),
            ("namespace_attribute_budget", f'<graphml xmlns="{GML}" '+ ' '.join(f'xmlns:q{i}="urn:q{i}:{seed}"' for i in range(65 + seed)) + '/>', r"resource limit exceeded: attributes_per_element", False),
        ]
        for category, xml, diagnostic, schema_reject in cases:
            yield Case(f"negative_{category}_{seed:02d}", category, xml, diagnostic, schema_must_reject=schema_reject)


EXTENSION_VOCABULARY = f'''<?xml version="1.0"?>
<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:e="{EXTENSION_NAMESPACE}"
 targetNamespace="{EXTENSION_NAMESPACE}" elementFormDefault="qualified">
 <xs:element name="payload"><xs:complexType><xs:sequence>
  <xs:element name="unit"><xs:complexType><xs:simpleContent><xs:extension base="xs:string">
   <xs:attribute name="scale" type="xs:positiveInteger" use="required"/>
  </xs:extension></xs:simpleContent></xs:complexType></xs:element>
 </xs:sequence><xs:attribute name="version" type="xs:nonNegativeInteger" use="required"/>
 </xs:complexType></xs:element>
</xs:schema>'''
EXTENSION_REDEFINE = f'''<?xml version="1.0"?>
<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:g="{GML}" xmlns:e="{EXTENSION_NAMESPACE}"
 targetNamespace="{GML}" elementFormDefault="qualified">
 <xs:import namespace="{EXTENSION_NAMESPACE}" schemaLocation="original-payload.xsd"/>
 <xs:redefine schemaLocation="{SCHEMA_BASE}graphml.xsd">
  <xs:complexType name="data-extension.type" mixed="true"><xs:complexContent mixed="true">
   <xs:extension base="g:data-extension.type"><xs:sequence>
    <xs:element ref="e:payload" minOccurs="0" maxOccurs="unbounded"/>
   </xs:sequence></xs:extension>
  </xs:complexContent></xs:complexType>
 </xs:redefine>
</xs:schema>'''


def load_schemas(cache: Path, offline: bool):
    cache.mkdir(parents=True, exist_ok=True)
    sources = []
    for name in SCHEMA_NAMES:
        url = SCHEMA_BASE + name
        path = cache / name
        if not path.exists():
            if offline:
                raise FileNotFoundError(f"official schema cache missing: {path}; rerun without --offline")
            with urllib.request.urlopen(url, timeout=30) as response:
                data = response.read(1024 * 1024)
                if len(data) == 1024 * 1024:
                    raise ValueError("unexpected oversized schema download")
                path.write_bytes(data)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != SCHEMA_SHA256[name]:
            raise ValueError(f"official schema hash mismatch for {name}: {digest}; the pinned standard must not be silently changed")
        sources.append({"url": url, "sha256": digest, "bytes": path.stat().st_size})
    # This is an original test vocabulary, not a change to the official schemas.
    (cache / "original-payload.xsd").write_text(EXTENSION_VOCABULARY, encoding="utf-8")
    (cache / "original-extension.xsd").write_text(EXTENSION_REDEFINE, encoding="utf-8")

    class OfficialResolver(etree.Resolver):
        def resolve(self, url, public_id, context):
            for name in SCHEMA_NAMES:
                if url == SCHEMA_BASE + name or url == str(cache / name):
                    return self.resolve_filename(str(cache / name), context)
            if url.endswith("/original-payload.xsd"):
                return self.resolve_filename(str(cache / "original-payload.xsd"), context)
            # Never fetch undeclared dependencies or arbitrary instance locators.
            if re.match(r"^[a-zA-Z]+://", url):
                raise ValueError(f"unexpected schema URL: {url}")
            return None

    parser = etree.XMLParser(no_network=True, resolve_entities=False, load_dtd=False)
    parser.resolvers.add(OfficialResolver())
    lxml_schemas = {
        "official": etree.XMLSchema(etree.parse(str(cache / "graphml.xsd"), parser)),
        "extension": etree.XMLSchema(etree.parse(str(cache / "original-extension.xsd"), parser)),
    }
    # libxml2 reports duplicated keyref matches for valid references inside
    # nested graphs. An independent XMLSchema 1.0 engine checks the *same*
    # unmodified standard correctly; the supplementary lxml discrepancy remains
    # recorded, not hidden or "fixed" by deleting identity constraints.
    mapping = {SCHEMA_BASE + name: str(cache / name) for name in SCHEMA_NAMES}
    primary_schemas = {
        "official": xmlschema.XMLSchema(str(cache / "graphml.xsd"), uri_mapper=mapping, allow="local"),
        "extension": xmlschema.XMLSchema(str(cache / "original-extension.xsd"), uri_mapper=mapping, allow="local"),
    }
    return primary_schemas, lxml_schemas, sources


def schema_accepts(schema, xml: str):
    try:
        root = etree.fromstring(xml.encode("utf-8"), etree.XMLParser(no_network=True, resolve_entities=False, load_dtd=False))
        if isinstance(schema, etree.XMLSchema):
            return schema.validate(root), str(schema.error_log.last_error or "")
        errors = list(schema.iter_errors(root))
        return not errors, str(errors[0]) if errors else ""
    except etree.XMLSyntaxError as error:
        return False, str(error)


def lxml_disagreement(case: Case, diagnostic: str) -> str:
    """Accept only independently reproduced libxml2 limitations, with evidence.

    Called only *after* the full unchanged official XSD has passed in xmlschema.
    Every new kind of disagreement is a failing test, not an automatic exception.
    """
    if "More than one match found for key-sequence" in diagnostic and case.category in {
        "nested_node_cross_level_reference", "nested_edge_graph",
    }:
        return "libxml2_nested_graph_keyref_false_rejection"
    if (case.category == "parse_advisory_arbitrary_precision_hints"
            and "SCHEMAV_CVC_DATATYPE_VALID_1_2_1" in diagnostic
            and "parse.outdegree" in diagnostic
            and "node.outdegree.type" in diagnostic):
        root = etree.fromstring(case.xml.encode("utf-8"))
        values = [element.get("parse.outdegree") for element in root.iter() if element.get("parse.outdegree") is not None]
        # The official restriction base is xs:nonNegativeInteger with no max
        # facet. Confirm exactly the tested legal unlimited-precision decimal.
        assert values and all(re.fullmatch(r"\+?[0-9]{25,}", value) for value in values), "arbitrary-precision discrepancy lacked a legal large decimal"
        return "libxml2_nonnegativeinteger_precision_false_rejection"
    raise AssertionError(f"unexplained XSD engine disagreement: {diagnostic}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, default=ROOT / "_build/native/release/build/cmd/graphml/graphml.exe")
    parser.add_argument("--positive-cases", type=int, default=120)
    parser.add_argument("--extension-cases", type=int, default=12)
    parser.add_argument("--negative-variants", type=int, default=4)
    parser.add_argument("--offline", action="store_true")
    options = parser.parse_args()
    if min(options.positive_cases, options.extension_cases, options.negative_variants) < 1:
        parser.error("case counts must be positive")
    executable = options.exe.resolve(strict=True)
    if not executable.is_file():
        parser.error("--exe must point to an existing native GraphML executable")
    artifacts = ROOT / ".local" / "standards-artifacts"
    artifacts.mkdir(parents=True, exist_ok=True)
    schemas, lxml_schemas, sources = load_schemas(ROOT / ".local" / "graphml-schema", options.offline)
    # Prove the original extension profile is genuinely strict. Deliberately
    # malformed payload vocabulary must be rejected by both independent engines.
    extension_sample = next(extension_cases(1)).xml
    invalid_extensions = {
        "positive_integer_scale": extension_sample.replace('scale="1"', 'scale="0"'),
        "required_version": extension_sample.replace(' version="0"', ''),
        "unknown_child": extension_sample.replace("e:unit", "e:unknown"),
        "unknown_attribute": extension_sample.replace('version="0"', 'version="0" unknown="x"'),
    }
    for name, xml in invalid_extensions.items():
        for engine in (schemas, lxml_schemas):
            accepted, reason = schema_accepts(engine["extension"], xml)
            assert not accepted, f"strict extension schema failed its guard check: {name}"
    positives = list(positive_cases(options.positive_cases)) + list(extension_cases(options.extension_cases))
    negatives = list(negative_cases(options.negative_variants))
    qname_cases = list(qname_context_cases(ROOT / ".local" / "graphml-schema" / "graphml-structure.xsd"))
    failures, passed_positive, passed_negative = [], Counter(), Counter()
    supplementary_disagreements = []
    identity_rejection_evidence = []
    passed_qname = Counter()
    qname_reverse_guards = 0
    xsi_type_engine_limitation = None
    started = time.perf_counter()

    def invoke(command: str, path: Path):
        if not path.is_file():
            raise AssertionError("test fixture did not exist before subprocess invocation")
        return subprocess.run([str(executable), command, str(path.resolve())], capture_output=True,
                              encoding="utf-8", errors="strict", timeout=30, check=False)

    for index, case in enumerate(positives):
        source = artifacts / f"{case.name}.graphml"
        source.write_text(case.xml, encoding="utf-8")
        try:
            accepted, reason = schema_accepts(schemas[case.schema_profile], case.xml)
            assert accepted, f"original fixture violates {case.schema_profile} schema: {reason}"
            if case.schema_profile == "extension":
                bare, bare_reason = schema_accepts(schemas["official"], case.xml)
                assert not bare, "the unextended official XSD unexpectedly allowed XML payload children"
            supplementary, other_reason = schema_accepts(lxml_schemas[case.schema_profile], case.xml)
            if not supplementary:
                kind = lxml_disagreement(case, other_reason)
                supplementary_disagreements.append({"case": case.name, "kind": kind, "error": other_reason})
            converted = invoke("roundtrip", source)
            assert converted.returncode == 0, f"roundtrip rc={converted.returncode}: {converted.stdout} {converted.stderr}"
            accepted, reason = schema_accepts(schemas[case.schema_profile], converted.stdout)
            assert accepted, f"emitted XML violates {case.schema_profile} schema: {reason}"
            supplementary, other_reason = schema_accepts(lxml_schemas[case.schema_profile], converted.stdout)
            if not supplementary:
                lxml_disagreement(case, other_reason)
            target = artifacts / f"{case.name}-emitted.graphml"
            target.write_text(converted.stdout, encoding="utf-8")
            verified = invoke("verify", source)
            assert verified.returncode == 0 and verified.stdout.strip() == "OK: model-equivalent roundtrip", (
                f"verify rc={verified.returncode}: {verified.stdout} {verified.stderr}")
            second = invoke("roundtrip", target)
            assert second.returncode == 0 and second.stdout == converted.stdout, "serialization not byte-deterministic after normalization"
            passed_positive[case.category] += 1
        except (AssertionError, subprocess.TimeoutExpired, UnicodeError, OSError) as error:
            failures.append({"case": case.name, "category": case.category, "direction": "positive", "error": str(error)})
        if (index + 1) % 25 == 0:
            print(f"Advanced positives: {index + 1}/{len(positives)}, failures={len(failures)}", flush=True)

    for index, case in enumerate(negatives):
        source = artifacts / f"{case.name}.graphml"
        source.write_text(case.xml, encoding="utf-8")
        try:
            # Unresolved entity nodes can make libxml2's XSD validator raise an
            # internal error. DTD security is a separate explicit prohibition,
            # not an XSD-invalid claim, so never hand these attack instances to
            # the schema engine or enable entity resolution to make it work.
            accepted, reason = (None, "DTD security profile, no XSD verdict") if case.xml.startswith("<!DOCTYPE") else schema_accepts(schemas["official"], case.xml)
            if case.schema_must_reject:
                if accepted and case.category == "duplicate_nested_node_port_name":
                    other_accepted, other_reason = schema_accepts(lxml_schemas["official"], case.xml)
                    assert not other_accepted and "Duplicate key-sequence" in other_reason and "port_name_key" in other_reason, (
                        f"missing independent normative descendant-port identity rejection: {other_reason}")
                    identity_rejection_evidence.append({"case": case.name, "xmlschema_accepts": True, "lxml_error": other_reason})
                    accepted = False
                assert not accepted, "negative fixture unexpectedly satisfies the official XSD"
            rejected = invoke("roundtrip", source)
            assert rejected.returncode == 1, f"expected validation rc=1, got {rejected.returncode}: {rejected.stdout} {rejected.stderr}"
            assert rejected.stdout.startswith("ERROR: "), f"missing validation diagnostic: {rejected.stdout} {rejected.stderr}"
            assert re.search(case.diagnostic, rejected.stdout), f"wrong diagnostic category; expected {case.diagnostic}: {rejected.stdout}"
            assert not rejected.stderr.strip(), f"unexpected runtime/OS stderr: {rejected.stderr}"
            passed_negative[case.category] += 1
        except (AssertionError, subprocess.TimeoutExpired, UnicodeError, OSError) as error:
            failures.append({"case": case.name, "category": case.category, "direction": "negative", "error": str(error)})
        if (index + 1) % 50 == 0:
            print(f"Negative/attack cases: {index + 1}/{len(negatives)}, failures={len(failures)}", flush=True)

    # Separate official-schema QName-value group. This requires an independent
    # expanded-type comparison in addition to MoonBit's own model equivalence.
    for case in qname_cases:
        source = artifacts / f"{case.name}.graphml"
        source.write_text(case.xml, encoding="utf-8")
        try:
            expected = expanded_type_signature(case.xml)
            accepted, reason = schema_accepts(lxml_schemas["official"], case.xml)
            assert accepted, f"legal xsi:type original violates unchanged official XSD: {reason}"
            rejected, reason = schema_accepts(lxml_schemas["official"], remove_qname_binding(case.xml))
            assert not rejected and "has no corresponding namespace declaration" in reason, f"source QName reverse guard did not reject for the right reason: {reason}"
            qname_reverse_guards += 1
            converted = invoke("roundtrip", source)
            assert converted.returncode == 0, f"QName roundtrip rc={converted.returncode}: {converted.stdout} {converted.stderr}"
            accepted, reason = schema_accepts(lxml_schemas["official"], converted.stdout)
            assert accepted, f"emitted xsi:type XML violates unchanged official XSD: {reason}"
            assert expanded_type_signature(converted.stdout) == expected, "expanded xsi:type QName changed/lost during serialization"
            rejected, reason = schema_accepts(lxml_schemas["official"], remove_qname_binding(converted.stdout))
            assert not rejected and "has no corresponding namespace declaration" in reason, f"emitted QName reverse guard did not reject for the right reason: {reason}"
            qname_reverse_guards += 1
            target = artifacts / f"{case.name}-emitted.graphml"
            target.write_text(converted.stdout, encoding="utf-8")
            verified = invoke("verify", source)
            assert verified.returncode == 0 and verified.stdout.strip() == "OK: model-equivalent roundtrip", (
                f"QName verify rc={verified.returncode}: {verified.stdout} {verified.stderr}")
            second = invoke("roundtrip", target)
            assert second.returncode == 0 and second.stdout == converted.stdout, "QName-context serialization not byte-deterministic"
            passed_qname[case.category] += 1
        except (AssertionError, subprocess.TimeoutExpired, UnicodeError, OSError) as error:
            failures.append({"case": case.name, "category": case.category, "direction": "qname_context", "error": str(error)})
    print(f"QName context positives: {sum(passed_qname.values())}/{len(qname_cases)}, reverse guards={qname_reverse_guards}, failures={len(failures)}", flush=True)

    # Capture the supplementary engine's actual limitation only after its
    # ordinary corpus is done. A RecursionError is not a schema validity verdict
    # and cannot stand in for a rejection or for a successful conversion.
    try:
        accepted, reason = schema_accepts(schemas["official"], qname_cases[0].xml)
        assert accepted, f"unexplained xmlschema xsi:type disagreement: {reason}"
        xsi_type_engine_limitation = {"case": qname_cases[0].name, "engine": "xmlschema", "version": xmlschema.__version__, "schema_valid": True, "exception": None}
    except RecursionError as error:
        xsi_type_engine_limitation = {
            "case": qname_cases[0].name, "engine": "xmlschema", "version": xmlschema.__version__,
            "schema_valid": None, "exception": type(error).__name__, "message": str(error),
            "fallback": "lxml validates the exact unchanged official XSD; all 11 QName source/emitted pairs and binding-removal rejection guards remain asserted",
        }
    except AssertionError as error:
        failures.append({"case": qname_cases[0].name, "category": "xsi_type_engine_limitation", "direction": "oracle", "error": str(error)})

    results = {
        "passed": not failures, "primary_xsd_engine": "xmlschema", "xmlschema_version": xmlschema.__version__,
        "lxml_version": etree.LXML_VERSION, "supplementary_lxml_disagreements": supplementary_disagreements,
        "xmlschema_nested_port_identity_disagreements": identity_rejection_evidence,
        "positive_cases": len(positives), "positive_passed": sum(passed_positive.values()),
        "negative_cases": len(negatives), "negative_passed": sum(passed_negative.values()),
        "qname_context_cases": len(qname_cases), "qname_context_passed": sum(passed_qname.values()),
        "qname_context_categories": dict(sorted(passed_qname.items())),
        "qname_context_primary_xsd_engine": "lxml",
        "qname_binding_removal_rejection_guards": qname_reverse_guards,
        "xmlschema_xsi_type_engine_limitation": xsi_type_engine_limitation,
        "positive_categories": dict(sorted(passed_positive.items())),
        "negative_categories": dict(sorted(passed_negative.items())),
        "schema_sources": sources, "original_extension_profile": EXTENSION_NAMESPACE,
        "original_extension_schema_sha256": hashlib.sha256(EXTENSION_REDEFINE.encode("utf-8")).hexdigest(),
        "strict_extension_schema_guard_checks": len(invalid_extensions) * 2,
        "official_schema_unmodified": True, "seconds": time.perf_counter() - started,
        "executable": str(executable), "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
        "failures": failures,
        "scope": "official GraphML structure/attributes/parseinfo XSD; typed values/scopes/port references/resource limits are explicit additional MoonGraphML checks; XML payload uses separately declared strict test vocabulary",
    }
    (ROOT / ".local" / "standards-results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(results, ensure_ascii=False, indent=2), flush=True)
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
