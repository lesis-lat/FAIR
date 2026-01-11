import json
import networkx as nx
from core.cache import save_graph, save_cache
from core.visualization import generate_html_from_files

CACHE_PATH = "cache.json"
GRAPH_PATH = "graph.json"

graph = nx.DiGraph()
graph.add_node("alice", full_name="Alice A.", count=2, followers=120, following=80)
graph.add_node("bob", full_name="Bob B.", count=1, followers=50, following=10)
graph.add_node("carol", full_name="Carol C.", count=1, followers=200, following=30)

graph.add_edge("alice", "bob", interactions=[{"type": "comment", "post_id": "p1"}], weight=1)
graph.add_edge("bob", "alice", interactions=[{"type": "mention", "post_id": "p2"}], weight=1)
graph.add_edge("alice", "carol", interactions=[{"type": "tag", "post_id": "p3"}], weight=1)

cache = {
    "alice": {"username": "alice", "full_name": "Alice A.", "followers": 120, "following": 80},
    "bob": {"username": "bob", "full_name": "Bob B.", "followers": 50, "following": 10},
    "carol": {"username": "carol", "full_name": "Carol C.", "followers": 200, "following": 30}
}

save_cache(CACHE_PATH, cache)
save_graph(GRAPH_PATH, graph)

generate_html_from_files(GRAPH_PATH, CACHE_PATH, "alice", suspicious_calc=False)
