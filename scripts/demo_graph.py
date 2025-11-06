"""Small demo to create a sample graph.json and cache.json and open the D3 HTML.

Run:
    python scripts/demo_graph.py
"""
import json
import networkx as nx
from core.cache import save_graph, save_cache
from core.visualization import generate_html_from_files

CACHE_PATH = "cache.json"
GRAPH_PATH = "graph.json"

# Build a tiny directed graph with interaction attributes
G = nx.DiGraph()
G.add_node("alice", full_name="Alice A.", count=2, followers=120, following=80)
G.add_node("bob", full_name="Bob B.", count=1, followers=50, following=10)
G.add_node("carol", full_name="Carol C.", count=1, followers=200, following=30)

G.add_edge("alice", "bob", interactions=[{"type": "comment", "post_id": "p1"}], weight=1)
G.add_edge("bob", "alice", interactions=[{"type": "mention", "post_id": "p2"}], weight=1)
G.add_edge("alice", "carol", interactions=[{"type": "tag", "post_id": "p3"}], weight=1)

# Minimal cache data for user display
cache = {
    "alice": {"username": "alice", "full_name": "Alice A.", "followers": 120, "following": 80},
    "bob": {"username": "bob", "full_name": "Bob B.", "followers": 50, "following": 10},
    "carol": {"username": "carol", "full_name": "Carol C.", "followers": 200, "following": 30}
}

# Save files
save_cache(CACHE_PATH, cache)
save_graph(GRAPH_PATH, G)

# Generate HTML and open it
generate_html_from_files(GRAPH_PATH, CACHE_PATH, "alice", suspicius_calc=False)
