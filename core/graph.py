from datetime import datetime

import matplotlib.pyplot as plt
import networkx as nx
import webbrowser

from core.api import extract_profile, fetch_posts, fetch_profile
from core.cache import save_cache, save_graph
from core.metrics import burstiness, entropy, temporal_entropy, transform_burstiness

def update_graph_node(graph, username, full_name=None, followers=0, following=0):
    if username not in graph:
        graph.add_node(
            username,
            count=1,
            full_name=full_name or username,
            followers=followers,
            following=following,
        )
        return
    graph.nodes[username]["count"] = graph.nodes[username].get("count", 1) + 1


def explore_users(
    username,
    api_keys,
    cache,
    cache_path,
    graph,
    explored,
    depth=1,
    max_depth=2,
    posts_limit=3,
    graph_path=None,
):
    if depth > max_depth or username in explored:
        return
    explored.add(username)

    profile_data = cache.get(username)
    if not profile_data:
        for key in api_keys:
            try:
                raw_data = fetch_profile(username, key)
                if raw_data:
                    profile_info = extract_profile(raw_data)
                    if profile_info:
                        posts = fetch_posts(username, key, posts_limit)
                        profile_info["latest_posts"] = posts
                        cache[username] = profile_info
                        save_cache(cache_path, cache)
                        profile_data = profile_info
                        if graph_path:
                            try:
                                save_graph(graph_path, graph)
                            except Exception:
                                pass
                        break
            except Exception:
                continue

    if not profile_data or profile_data.get("account_type") == "Private":
        return

    update_graph_node(
        graph,
        username,
        full_name=profile_data.get("full_name", username),
        followers=profile_data.get("followers", 0),
        following=profile_data.get("following", 0),
    )

    if "latest_posts" not in profile_data:
        return

    for post in profile_data["latest_posts"]:
        relations = [
            ("mentions", "mention"),
            ("tagged_users", "tag"),
            ("commenters", "comment"),
        ]

        for relation_key, interaction_type in relations:
            for related_user in post.get(relation_key, []):
                if not related_user or related_user == username:
                    continue

                update_graph_node(graph, related_user, full_name=related_user)

                if graph.has_edge(username, related_user):
                    edge_data = graph.get_edge_data(username, related_user) or {}
                    interactions = edge_data.get("interactions", [])
                    interactions.append({"type": interaction_type, "post_id": post.get("id")})
                    edge_data["interactions"] = interactions
                    edge_data["weight"] = edge_data.get("weight", 1) + 1
                    graph.add_edge(username, related_user, **edge_data)
                if not graph.has_edge(username, related_user):
                    graph.add_edge(
                        username,
                        related_user,
                        interactions=[{"type": interaction_type, "post_id": post.get("id")}],
                        weight=1,
                    )

                explore_users(
                    related_user,
                    api_keys,
                    cache,
                    cache_path,
                    graph,
                    explored,
                    depth=depth + 1,
                    max_depth=max_depth,
                    posts_limit=posts_limit,
                    graph_path=graph_path,
                )

def compute_suspicious_scores(cache, graph, main_user):
    for node in graph.nodes:
        if node == main_user:
            continue
        if graph.degree(node) != 1 or not graph.has_edge(main_user, node):
            continue

        profile = cache.get(node)
        if not profile or "latest_posts" not in profile:
            continue

        posts = profile["latest_posts"]
        post_dates = []
        total_interactions = 0

        for post in posts:
            date_val = post.get("date")
            parsed_datetime = None
            try:
                parsed_datetime = datetime.strptime(date_val, "%Y-%m-%dT%H:%M:%S.%fZ")
            except Exception:
                try:
                    parsed_datetime = datetime.fromtimestamp(float(date_val))
                except Exception:
                    continue
            if parsed_datetime:
                post_dates.append(parsed_datetime)
            total_interactions += post.get("likes", 0) + post.get("comments", 0)

        post_dates.sort()
        has_posts = bool(post_dates)

        temporal = 0.0
        burstiness_score = 0.0
        avg_interactions = 0.0
        if has_posts:
            temporal = temporal_entropy(post_dates)
            burstiness_score = burstiness(post_dates)
        if posts:
            avg_interactions = total_interactions / len(posts)

        name_entropy = entropy(profile.get("full_name", ""))
        username_entropy = entropy(profile.get("username", ""))
        followers = profile.get("followers", 0)
        engagement_ratio = 0.0
        if followers > 0:
            engagement_ratio = avg_interactions / followers
        threshold = 1 / 200
        engagement_score = 1.0
        if engagement_ratio < threshold:
            engagement_score = engagement_ratio / threshold

        username_score = 1 / (1 + username_entropy)
        name_score = 1 / (1 + name_entropy)

        final_score = 0.0
        if has_posts:
            temporal_score_adj = 1 / (1 + (temporal / 2))
            temporal_fuzzy = transform_burstiness(temporal_score_adj)
            burst_fuzzy = transform_burstiness(burstiness_score)
            engage_fuzzy = transform_burstiness(engagement_score)
            uname_fuzzy = transform_burstiness(username_score)
            name_fuzzy = transform_burstiness(name_score)

            final_score = 0.35 * burst_fuzzy + 0.25 * temporal_fuzzy + 0.2 * engage_fuzzy + 0.15 * uname_fuzzy + 0.05 * name_fuzzy
        if not has_posts:
            engage_fuzzy = transform_burstiness(engagement_score)
            uname_fuzzy = transform_burstiness(username_score)
            name_fuzzy = transform_burstiness(name_score)

            final_score = 0.4 * engage_fuzzy + 0.35 * uname_fuzzy + 0.25 * name_fuzzy

        profile["suspicious_score"] = {
            "temporal_entropy": temporal,
            "name_entropy": name_entropy,
            "username_entropy": username_entropy,
            "burstiness": burstiness_score,
            "engagement_score": engagement_score,
            "final_score": final_score
        }


def generate_html(graph, explored_users, main_user, cache, suspicious_calc=False):
    subgraph = graph.copy()
    if suspicious_calc:
        allowed_nodes = {main_user} | set(graph.neighbors(main_user))
        subgraph = graph.subgraph(allowed_nodes).copy()
    if not suspicious_calc:
        isolated = []
        for node in graph.nodes:
            if node in explored_users:
                continue
            isolated.append(node)
        subgraph = graph.copy()
        subgraph.remove_nodes_from(isolated)

    positions = nx.spring_layout(subgraph)
    for node in subgraph.nodes():
        subgraph.nodes[node].setdefault("count", 1)

    color_map = {}
    for node in subgraph.nodes():
        score = cache.get(node, {}).get("suspicious_score", {}).get("final_score", 0)
        color_map[node] = "#dddddd"
        if node == main_user:
            color_map[node] = "#6699cc"
        if color_map[node] == "#dddddd" and suspicious_calc and score >= 0.6:
            color_map[node] = "#FF0000"
        if color_map[node] == "#dddddd" and node != main_user and subgraph.degree(node) == 1:
            color_map[node] = "#ffb6c1"
        if color_map[node] == "#dddddd" and main_user in list(subgraph.neighbors(node)):
            color_map[node] = "#75c793"

    labels = {node: node for node in subgraph.nodes()}
    node_sizes = [max(100, subgraph.nodes[node]['count'] * 100) for node in subgraph.nodes()]
    node_colors = [color_map.get(node, "#dddddd") for node in subgraph.nodes()]

    fig, ax = plt.subplots()
    fig.set_facecolor("white")
    ax.set_facecolor("white")
    nx.draw_networkx_nodes(subgraph, positions, node_size=node_sizes, node_color=node_colors, ax=ax)
    nx.draw_networkx_edges(subgraph, positions, edge_color="black", width=1.0, ax=ax)
    nx.draw_networkx_labels(subgraph, positions, labels=labels, font_size=10, font_weight="bold",
                            bbox=dict(boxstyle="round", fc="none", ec="none"), ax=ax)
    ax.set_axis_off()

    svg_file = f"graph_{main_user}.svg"
    html_file = f"graph_{main_user}.html"
    try:
        fig.savefig(svg_file, format="svg", bbox_inches="tight")
        with open(html_file, "w", encoding="utf-8") as f:
            f.write(f"""<!doctype html>
<html lang=\"en\"> 
<head>
  <meta charset=\"utf-8\"> 
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"> 
  <title>Graph {main_user}</title>
  <style>body{{margin:0;padding:0;display:flex;flex-direction:column;align-items:center}}svg{{width:100%;height:auto}}</style>
</head>
<body>
  <h2 style=\"font-family:Arial,Helvetica,sans-serif;\">Graph for {main_user}</h2>
  <object type=\"image/svg+xml\" data=\"{svg_file}\">Your browser does not support SVG</object>
</body>
</html>
""")
    finally:
        plt.close(fig)

    try:
        webbrowser.open_new_tab(html_file)
    except Exception:
        pass
