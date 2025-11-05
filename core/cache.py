import os
import json
import networkx as nx


def load_cache(path):
    if not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as file:
        try:
            return json.load(file)
        except json.JSONDecodeError:
            return {}


def save_cache(path, data):
    with open(path, "w", encoding="utf-8") as file:
        json.dump(data, file, indent=4)


def save_graph(path, graph: nx.Graph):
    """Serialize a NetworkX graph (directed or undirected) to a JSON file.

    Format:
    {
        "directed": true|false,
        "nodes": [{"id": node_id, "attributes": { ... }}, ...],
        "edges": [{"source": u, "target": v, "attributes": { ... }}, ...]
    }
    """
    data = {
        "directed": bool(graph.is_directed()),
        "nodes": [],
        "edges": []
    }

    for n, attrs in graph.nodes(data=True):
        try:
            # ensure attributes are JSON serializable
            json.dumps(attrs)
            node_attrs = attrs
        except Exception:
            # fallback: coerce to string for problematic attributes
            node_attrs = {k: str(v) for k, v in attrs.items()}

        data["nodes"].append({"id": n, "attributes": node_attrs})

    for u, v, attrs in graph.edges(data=True):
        try:
            json.dumps(attrs)
            edge_attrs = attrs
        except Exception:
            edge_attrs = {k: str(v) for k, v in attrs.items()}

        data["edges"].append({"source": u, "target": v, "attributes": edge_attrs})

    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4)


def load_graph(path):
    """Load a graph previously saved with save_graph. Returns a NetworkX Graph/DiGraph.

    If the file does not exist or is invalid, returns an empty DiGraph by default.
    """
    if not os.path.exists(path):
        return nx.DiGraph()

    with open(path, "r", encoding="utf-8") as f:
        try:
            payload = json.load(f)
        except json.JSONDecodeError:
            return nx.DiGraph()

    directed = payload.get("directed", True)
    G = nx.DiGraph() if directed else nx.Graph()

    for node in payload.get("nodes", []):
        nid = node.get("id")
        attrs = node.get("attributes", {})
        G.add_node(nid, **attrs)

    for edge in payload.get("edges", []):
        u = edge.get("source")
        v = edge.get("target")
        attrs = edge.get("attributes", {})
        G.add_edge(u, v, **attrs)

    return G