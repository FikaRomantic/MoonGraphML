"""Independent induced-subgraph and CSR CLI checks; all results stay in .local.

Uses NetworkX only as a separately installed oracle, not copied implementation.
CSR is checked by an independent XML/endpoint scan, including mixed directions.
No SciPy installation or all-GraphML compatibility is claimed by this script.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import random
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".local" / "oracles"))
import networkx as nx

NS = "http://graphml.graphdrawing.org/xmlns"
ET.register_namespace("", NS)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def fixture(seed, mixed=False):
    rng = random.Random(seed)
    count = seed % 13
    ids = [f"n{i}" for i in range(count)]
    if ids:
        ids[-1] = "孤立🌙"  # legal GraphML NMTOKEN and multi-byte CLI argument
    directed = seed % 2 == 0
    root = ET.Element(f"{{{NS}}}graphml")
    ET.SubElement(root, f"{{{NS}}}key", {
        "id": "w", "for": "edge", "attr.name": "weight", "attr.type": "long",
    })
    graph = ET.SubElement(root, f"{{{NS}}}graph", {
        "id": "G", "edgedefault": "directed" if directed else "undirected",
    })
    for node_id in ids:
        ET.SubElement(graph, f"{{{NS}}}node", {"id": node_id})
    for i in range(count * 3):
        # Keep the final vertex isolated when there are multiple vertices.
        candidates = ids[:-1] if count > 1 else ids
        attr = {"id": f"e{i}", "source": rng.choice(candidates), "target": rng.choice(candidates)}
        if mixed and i % 3 == 0:
            attr["directed"] = "false" if directed else "true"
        edge = ET.SubElement(graph, f"{{{NS}}}edge", attr)
        ET.SubElement(edge, f"{{{NS}}}data", {"key": "w"}).text = str(9007199254740993 + i)
    return ET.tostring(root, encoding="unicode"), ids


def signature(graph):
    nodes = sorted((node, tuple(sorted(data.items()))) for node, data in graph.nodes(data=True))
    edges = []
    for source, target, key, data in graph.edges(keys=True, data=True):
        if not graph.is_directed() and source > target:
            source, target = target, source
        edges.append((source, target, str(key), tuple(sorted(data.items()))))
    return nodes, sorted(edges)


def check_csr(xml, payload, incoming):
    graph = ET.fromstring(xml).find(f"{{{NS}}}graph")
    ids = [node.attrib["id"] for node in graph.findall(f"{{{NS}}}node")]
    lookup = {node: i for i, node in enumerate(ids)}
    edges = graph.findall(f"{{{NS}}}edge")
    rows = [[] for _ in ids]
    for i, edge in enumerate(edges):
        source, target = lookup[edge.attrib["source"]], lookup[edge.attrib["target"]]
        directed = edge.attrib.get("directed", str(graph.attrib["edgedefault"] == "directed").lower()) == "true"
        if directed:
            if incoming:
                rows[target].append((source, i, True))
            else:
                rows[source].append((target, i, False))
        else:
            rows[source].append((target, i, False))
            if source != target:
                rows[target].append((source, i, True))
    pointers, indices, originals, reverse = [0], [], [], []
    for row in rows:
        for target, original, reversed_arc in row:
            indices.append(target)
            originals.append(original)
            reverse.append(reversed_arc)
        pointers.append(len(indices))
    expected = {"node_ids": ids, "indptr": pointers, "indices": indices,
                "edge_indices": originals, "reversed": reverse,
                "orientation": "incoming" if incoming else "outgoing"}
    require(payload == expected, "CSR disagrees with independent endpoint scan")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--executable", type=Path, default=ROOT / "_build/native/debug/build/cmd/graphml/graphml.exe")
    parser.add_argument("--cases", type=int, default=100)
    args = parser.parse_args()
    require(args.cases > 0, "cases must be positive")
    executable = args.executable.resolve(strict=True)
    report = {"passed": False, "networkx": nx.__version__, "networkx_subgraphs": 0,
              "csr_endpoint_checks": 0, "cli_error_checks": 0,
              "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest()}
    result_path = ROOT / ".local" / "adapters-results-20261022.json"
    with tempfile.TemporaryDirectory(prefix="adapter-cases-", dir=ROOT / ".local") as directory:
        source = Path(directory) / "input.graphml"

        def invoke(command, *extra, expected=0):
            result = subprocess.run([str(executable), command, str(source), *extra],
                                    capture_output=True, encoding="utf-8", timeout=30)
            require(result.returncode == expected,
                    f"{command} exit {result.returncode}, expected {expected}: {result.stdout} {result.stderr}")
            return result.stdout

        try:
            for seed in range(args.cases):
                xml, ids = fixture(seed)
                source.write_text(xml, encoding="utf-8")
                selection = [node for i, node in reversed(list(enumerate(ids))) if (seed + i) % 3 != 0]
                output = invoke("subgraph", *selection)
                original = nx.read_graphml(io.StringIO(xml), edge_key_type=str, force_multigraph=True)
                recovered = nx.read_graphml(io.StringIO(output), edge_key_type=str, force_multigraph=True)
                require(signature(original.subgraph(selection)) == signature(recovered),
                        f"NetworkX induced-subgraph mismatch at seed {seed}")
                report["networkx_subgraphs"] += 1
                for mixed in (False, True):
                    candidate, _ = fixture(seed, mixed=mixed)
                    source.write_text(candidate, encoding="utf-8")
                    for incoming in (False, True):
                        payload = json.loads(invoke("csr-incoming" if incoming else "csr"))
                        check_csr(candidate, payload, incoming)
                        report["csr_endpoint_checks"] += 1
            source.write_text(fixture(2)[0], encoding="utf-8")
            for selection in (("missing",), ("n0", "n0")):
                require(invoke("subgraph", *selection, expected=1).startswith("ERROR:"), "missing diagnostic")
                report["cli_error_checks"] += 1
            invoke("csr", "unexpected", expected=2)
            report["cli_error_checks"] += 1
            source.write_text(
                f"<graphml xmlns='{NS}'><graph edgedefault='directed'/><graph edgedefault='directed'/></graphml>",
                encoding="utf-8")
            for command in ("csr", "csr-incoming", "subgraph"):
                invoke(command, expected=1)
                report["cli_error_checks"] += 1
            source.write_text(
                f"<graphml xmlns='{NS}'><graph edgedefault='directed'><node id='a'><port name='p'/></node></graph></graphml>",
                encoding="utf-8")
            for command in ("csr", "csr-incoming", "subgraph"):
                invoke(command, expected=1)
                report["cli_error_checks"] += 1
            report["passed"] = True
        finally:
            result_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
