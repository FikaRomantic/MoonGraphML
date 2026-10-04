"""Independent, reproducible GraphML differential tests. All artifacts stay in .local.

No reference-library implementation is copied. The tested common profile is flat,
uniformly directed/undirected multigraphs with scalar attributes. NetworkX defaults
are explicitly expanded before re-export, as documented by its GraphML API.
igraph's integer attributes are doubles: only exactly representable integers are
in its common profile. GraphML IDs/unused declarations/XML metadata are not part
of this scalar graph comparison. Advanced structures are tested separately.
"""
from __future__ import annotations

import argparse
import io
import json
import math
from pathlib import Path
import random
import subprocess
import sys
import time
import warnings

ROOT = Path(__file__).resolve().parents[1]
ORACLES = ROOT / ".local" / "oracles"
if ORACLES.exists():
    sys.path.insert(0, str(ORACLES))
import networkx as nx
import igraph as ig


def stable(value):
    if isinstance(value, dict):
        return tuple(sorted((str(k), stable(v)) for k, v in value.items()))
    if isinstance(value, (list, tuple)):
        return tuple(stable(v) for v in value)
    if isinstance(value, float) and math.isnan(value):
        return ("nonfinite", "NaN")
    if isinstance(value, float) and math.isinf(value):
        return ("nonfinite", "INF" if value > 0 else "-INF")
    return value


def expand_nx_defaults(graph):
    for _, data in graph.nodes(data=True):
        for key, value in graph.graph.get("node_default", {}).items():
            data.setdefault(key, value)
    for *_, data in graph.edges(data=True):
        for key, value in graph.graph.get("edge_default", {}).items():
            data.setdefault(key, value)
    return graph


def nx_signature(graph):
    expand_nx_defaults(graph)
    nodes = tuple(sorted((str(node), stable(data)) for node, data in graph.nodes(data=True)))
    edges = []
    for source, target, key, data in graph.edges(keys=True, data=True):
        source, target = str(source), str(target)
        if not graph.is_directed() and target < source:
            source, target = target, source
        # Parallel-edge identity is retained as well as multiplicity and endpoints.
        edges.append((source, target, str(key), stable(data)))
    graph_data = {k: v for k, v in graph.graph.items() if k not in {"node_default", "edge_default"}}
    return graph.is_directed(), nodes, tuple(sorted(edges)), stable(graph_data)


def read_nx(xml):
    return nx.read_graphml(io.BytesIO(xml.encode("utf-8")), edge_key_type=str, force_multigraph=True)


def write_nx(graph):
    buffer = io.BytesIO()
    nx.write_graphml(expand_nx_defaults(graph), buffer, encoding="utf-8")
    return buffer.getvalue().decode("utf-8")


def nx_fixture(seed):
    rng = random.Random(seed)
    graph = nx.MultiDiGraph() if seed % 2 == 0 else nx.MultiGraph()
    graph.graph["title"] = f"dataset {seed} 中文 <&>"
    graph.graph["node_default"] = {"count": 7}
    graph.graph["edge_default"] = {"weight": 1.5}
    count = 1 + seed % 11
    for node in range(count):
        attrs = {"label": f"节点 {node}\n\t😀<&>", "active": node % 2 == 0,
                 "large": 9007199254740993 + seed, "score": node / 4.0}
        if node % 2 == 0:
            attrs["count"] = seed + node
        graph.add_node(f"n{node}", **attrs)
    for edge in range(seed % 19):
        source = 0 if edge < 3 else rng.randrange(count)
        target = source if edge == 0 else count - 1 if edge < 3 else rng.randrange(count)
        attrs = {"weight": (seed + edge) / 2.0} if edge % 2 == 0 else {}
        graph.add_edge(f"n{source}", f"n{target}", key=f"e{edge}", **attrs)
    return write_nx(graph)


def ig_signature(graph):
    vertices = tuple(stable({key: graph.vs[i][key] for key in graph.vertex_attributes()})
                     for i in range(graph.vcount()))
    edges = []
    for edge in graph.es:
        source, target = edge.tuple
        if not graph.is_directed() and target < source:
            source, target = target, source
        edges.append((source, target, stable(edge.attributes())))
    return graph.is_directed(), vertices, tuple(sorted(edges)), stable({key: graph[key] for key in graph.attributes()})


def ig_fixture(seed, path):
    count = 1 + seed % 11
    edges = [(0, 0), (0, count - 1), (0, count - 1)]
    edges += [(i % count, (i * 3 + seed) % count) for i in range(seed % 13)]
    graph = ig.Graph(n=count, edges=edges, directed=seed % 2 == 0)
    graph["title"] = f"igraph {seed} 中文 <&>"
    graph.vs["name"] = [f"v{i}" for i in range(count)]
    graph.vs["label"] = [f"节点 {i} 😀<&>" for i in range(count)]
    graph.vs["active"] = [i % 2 == 0 for i in range(count)]
    graph.vs["score"] = [i / 4.0 for i in range(count)]
    graph.es["weight"] = [i / 2.0 for i in range(len(edges))]
    graph.write_graphml(str(path))
    return path.read_text(encoding="utf-8")


def moon_fixture_for_igraph(seed):
    # Original fixtures for the MoonBit emitter/parser direction. Finite doubles,
    # booleans and strings are within igraph's precision and attribute profile.
    from xml.sax.saxutils import escape
    count = 1 + seed % 9
    nodes = "".join(f'<node id="n{i}"><data key="name">n{i}</data><data key="label">'
                    f'{escape(f"节点 {i} 😀<&>")}</data><data key="score">{i / 4.0}</data></node>'
                    for i in range(count))
    edges = "".join(f'<edge source="n{i % count}" target="n{(i * 3 + seed) % count}">'
                    f'<data key="weight">{i / 2.0}</data></edge>' for i in range(3 + seed % 11))
    direction = "directed" if seed % 2 == 0 else "undirected"
    return '<graphml xmlns="http://graphml.graphdrawing.org/xmlns">' + (
        '<key id="name" for="node" attr.name="name" attr.type="string"/>'
        '<key id="label" for="node" attr.name="label" attr.type="string"/>'
        '<key id="score" for="node" attr.name="score" attr.type="double"/>'
        '<key id="weight" for="edge" attr.name="weight" attr.type="double"/>') + (
        f'<graph edgedefault="{direction}">{nodes}{edges}</graph></graphml>')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--exe", type=Path, default=ROOT / "_build/native/release/build/cmd/graphml/graphml.exe")
    parser.add_argument("--networkx-cases", type=int, default=500)
    parser.add_argument("--igraph-cases", type=int, default=300)
    parser.add_argument("--igraph-start", type=int, default=0)
    parser.add_argument("--igraph-worker", action="store_true")
    options = parser.parse_args()
    if options.networkx_cases < 0 or options.igraph_cases < 1 or options.igraph_start < 0:
        parser.error("case counts must be positive")
    artifacts = ROOT / ".local" / "interop-artifacts"
    artifacts.mkdir(parents=True, exist_ok=True)
    source_path = artifacts / "source.graphml"
    exported_path = artifacts / "exported.graphml"
    reexported_path = artifacts / "reexported.graphml"

    def run(command, arg):
        completed = subprocess.run([str(options.exe.resolve()), command, str(arg)],
                                   check=True, capture_output=True, encoding="utf-8", timeout=30)
        return completed.stdout.strip()

    def roundtrip(xml):
        source_path.write_text(xml, encoding="utf-8")
        return run("roundtrip-compatible", source_path)

    started = time.perf_counter()
    for seed in range(options.networkx_cases):
        source = nx_fixture(seed)
        expected = nx_signature(read_nx(source))
        emitted = roundtrip(source)
        assert nx_signature(read_nx(emitted)) == expected, ("NetworkX -> MoonBit", seed)
        own = run("generate", seed)
        expected = nx_signature(read_nx(own))
        reexported = write_nx(read_nx(own))
        recovered = roundtrip(reexported)
        assert nx_signature(read_nx(recovered)) == expected, ("MoonBit -> NetworkX -> MoonBit", seed)
        if (seed + 1) % 100 == 0:
            print(f"NetworkX: {seed + 1}/{options.networkx_cases} cases, both directions passed", flush=True)
    if not options.igraph_worker:
        # Isolate bounded batches: repeated GraphML calls in the Windows igraph
        # binary can exhaust CRT file descriptors. Every case still asserts both
        # directions; a worker failure stops the parent rather than being skipped.
        for start in range(0, options.igraph_cases, 50):
            count = min(50, options.igraph_cases - start)
            subprocess.run([sys.executable, str(Path(__file__).resolve()), "--exe", str(options.exe.resolve()),
                            "--networkx-cases", "0", "--igraph-cases", str(count),
                            "--igraph-start", str(start), "--igraph-worker"], check=True, timeout=120)
            print(f"igraph: {start + count}/{options.igraph_cases} cases, both directions passed", flush=True)
    for seed in range(options.igraph_start, options.igraph_start + options.igraph_cases) if options.igraph_worker else []:
        source = ig_fixture(seed, source_path)
        expected = ig_signature(ig.Graph.Read_GraphML(str(source_path)))
        emitted = roundtrip(source)
        exported_path.write_text(emitted, encoding="utf-8")
        assert ig_signature(ig.Graph.Read_GraphML(str(exported_path))) == expected, ("igraph -> MoonBit", seed)
        own = roundtrip(moon_fixture_for_igraph(seed))
        exported_path.write_text(own, encoding="utf-8")
        graph = ig.Graph.Read_GraphML(str(exported_path))
        baseline = ig_signature(graph)
        graph.write_graphml(str(reexported_path))
        assert ig_signature(ig.Graph.Read_GraphML(str(reexported_path))) == baseline, ("igraph self-roundtrip", seed)
        recovered = roundtrip(reexported_path.read_text(encoding="utf-8"))
        exported_path.write_text(recovered, encoding="utf-8")
        assert ig_signature(ig.Graph.Read_GraphML(str(exported_path))) == baseline, ("MoonBit -> igraph -> MoonBit", seed)
        if (seed + 1) % 100 == 0:
            print(f"igraph: {seed + 1}/{options.igraph_cases} cases, both directions passed", flush=True)
    results = {
        "networkx_version": nx.__version__, "igraph_version": ig.__version__,
        "networkx_cases": options.networkx_cases, "igraph_cases": options.igraph_cases,
        "directions_per_case": 2, "failed": 0, "seconds": time.perf_counter() - started,
        "profile": "flat scalar multigraph; defaults explicitly expanded; igraph finite-double subset",
    }
    if not options.igraph_worker:
        (ROOT / ".local" / "interop-results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(json.dumps(results, ensure_ascii=False, indent=2), flush=True)


if __name__ == "__main__":
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        # igraph warns when its own writer preserves the already materialized ID
        # attribute. Equality above explicitly checks that it has not changed.
        warnings.filterwarnings("ignore", message="Could not add vertex ids, there is already an 'id' vertex attribute.*", category=RuntimeWarning)
        main()
