import json
import os

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


def _coerce_json_attributes(attributes):
    try:
        json.dumps(attributes)
        return attributes
    except TypeError:
        return {key: str(value) for key, value in attributes.items()}


def save_graph(path, graph: nx.Graph):
    payload = {
        "directed": bool(graph.is_directed()),
        "nodes": [],
        "edges": [],
    }

    for node_id, attributes in graph.nodes(data=True):
        payload["nodes"].append(
            {"id": node_id, "attributes": _coerce_json_attributes(attributes)}
        )

    for source, target, attributes in graph.edges(data=True):
        payload["edges"].append(
            {"source": source, "target": target, "attributes": _coerce_json_attributes(attributes)}
        )

    with open(path, "w", encoding="utf-8") as file:
        json.dump(payload, file, indent=4)


def load_graph(path):
    if not os.path.exists(path):
        return nx.DiGraph()

    with open(path, "r", encoding="utf-8") as file:
        try:
            payload = json.load(file)
        except json.JSONDecodeError:
            return nx.DiGraph()

    is_directed = payload.get("directed", True)
    graph = nx.DiGraph() if is_directed else nx.Graph()

    for node in payload.get("nodes", []):
        node_id = node.get("id")
        attributes = node.get("attributes", {})
        graph.add_node(node_id, **attributes)

    for edge in payload.get("edges", []):
        source = edge.get("source")
        target = edge.get("target")
        attributes = edge.get("attributes", {})
        graph.add_edge(source, target, **attributes)

    return graph
