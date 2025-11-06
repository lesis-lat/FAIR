import argparse
import json
import networkx as nx
from core.api import load_api_keys
from core.cache import load_cache, save_cache
from core.graph import explore_users, compute_suspicious_scores
from core.visualization import generate_html_from_files


def main():
    parser = argparse.ArgumentParser(description="FAIR - Fake Account Interaction Recognition")
    parser.add_argument("--username", required=True, help="Instagram username to analyze")
    parser.add_argument("--depth", type=int, default=2, help="Recursion depth (default: 2)")
    parser.add_argument("--posts", type=int, default=3, help="Number of posts to analyze (default: 3)")
    parser.add_argument("--no-cache", action="store_true", help="Ignore existing cache and generate new data")
    parser.add_argument("--suspicious-calc", action="store_true",
                        help="Enable suspicious score calculation and red highlighting for suspicious nodes")
    
    args = parser.parse_args()

    username = args.username
    max_depth = args.depth
    posts_limit = args.posts
    cache_path = "cache.json"

    print("[INFO] API keys and cache loaded successfully.")
    print(f"Analyzing user: {username} (depth={max_depth}, posts={posts_limit})")

    if args.no_cache:
        cache = {}
    else:
        cache = load_cache(cache_path)

    api_keys = load_api_keys("keys.env")
    graph = nx.DiGraph()
    explored_users = set()

    print("[INFO] Starting recursive exploration and graph generation...")
    
    # Persist graph to disk alongside cache for later visualization
    graph_path = "graph.json"
    explore_users(username, api_keys, cache, cache_path, graph, explored_users,
                  max_depth=max_depth, posts_limit=posts_limit, graph_path=graph_path)

    if args.suspicious_calc:
        compute_suspicious_scores(cache, graph, username)

    save_cache(cache_path, cache)
    # Save graph structure to disk (nodes, edges, attributes)
    try:
        from core.cache import save_graph
        save_graph(graph_path, graph)
    except Exception:
        pass
    # Generate a dynamic, D3-based HTML from the persisted files
    try:
        generate_html_from_files(graph_path, cache_path, username, suspicius_calc=args.suspicious_calc)
    except Exception:
        # fallback to the older in-memory generator if present
        try:
            from core.graph import generate_html as legacy_generate
            legacy_generate(graph, explored_users, username, cache, suspicius_calc=args.suspicious_calc)
        except Exception:
            pass

    if username in cache:
        print(json.dumps(cache[username], indent=4))

if __name__ == "__main__":
    main()