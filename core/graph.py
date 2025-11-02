import networkx as nx
import matplotlib.pyplot as plt
import webbrowser
from datetime import datetime
from core.metrics import entropy, temporal_entropy, burstiness, transform_burstiness
from core.cache import save_cache
from core.api import fetch_profile, extract_profile, fetch_posts

def update_graph_node(graph, user, full_name=None, followers=0, following=0):
    if user not in graph:
        graph.add_node(user, count=1, full_name=full_name or user, followers=followers, following=following)
    else:
        graph.nodes[user]["count"] = graph.nodes[user].get("count", 1) + 1

def explore_users(username, api_keys, cache, cache_path, graph, explored, depth=1, max_depth=2, posts_limit=3):
    if depth > max_depth or username in explored:
        return
    explored.add(username)

    user_data = cache.get(username)
    if not user_data:
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
                        user_data = profile_info
                        break
            except Exception:
                continue

    if not user_data or user_data.get("account_type") == "Private":
        return

    update_graph_node(graph, username, full_name=user_data.get("full_name", username),
                      followers=user_data.get("followers", 0), following=user_data.get("following", 0))

    if "latest_posts" not in user_data:
        return

    for post in user_data["latest_posts"]:
        for relation in (post.get("mentions", []), post.get("tagged_users", []), post.get("commenters", [])):
            for related_user in relation:
                if related_user and related_user != username:
                    update_graph_node(graph, related_user, full_name=related_user)
                    graph.add_edge(username, related_user)
                    explore_users(related_user, api_keys, cache, cache_path, graph, explored,
                                  depth=depth + 1, max_depth=max_depth, posts_limit=posts_limit)

def compute_suspicious_scores(cache, graph, main_user):
    for node in graph.nodes:
        if node == main_user:
            continue
        if graph.degree(node) != 1 or not graph.has_edge(main_user, node):
            continue  # skip if not strictly isolated

        profile = cache.get(node)
        if not profile or "latest_posts" not in profile:
            continue

        posts = profile["latest_posts"]
        post_dates = []
        total_interactions = 0

        for post in posts:
            date_val = post.get("date")
            dt = None
            try:
                dt = datetime.strptime(date_val, "%Y-%m-%dT%H:%M:%S.%fZ")
            except Exception:
                try:
                    dt = datetime.fromtimestamp(float(date_val))
                except Exception:
                    continue
            if dt:
                post_dates.append(dt)
            total_interactions += post.get("likes", 0) + post.get("comments", 0)

        post_dates.sort()
        posts_available = bool(post_dates)

        temporal = temporal_entropy(post_dates) if posts_available else 0.0
        bursts = burstiness(post_dates) if posts_available else 0.0
        avg_interactions = total_interactions / len(posts) if posts else 0.0

        name_ent = entropy(profile.get("full_name", ""))
        username_ent = entropy(profile.get("username", ""))
        followers = profile.get("followers", 0)
        engagement_ratio = avg_interactions / followers if followers > 0 else 0.0
        threshold = 1 / 200
        engagement_score = engagement_ratio / threshold if engagement_ratio < threshold else 1.0

        username_score = 1 / (1 + username_ent)
        name_score = 1 / (1 + name_ent)

        if posts_available:
            temporal_score_adj = 1 / (1 + (temporal / 2))
            temporal_fuzzy = transform_burstiness(temporal_score_adj)
            burst_fuzzy = transform_burstiness(bursts)
            engage_fuzzy = transform_burstiness(engagement_score)
            uname_fuzzy = transform_burstiness(username_score)
            name_fuzzy = transform_burstiness(name_score)

            final = 0.35 * burst_fuzzy + 0.25 * temporal_fuzzy + 0.2 * engage_fuzzy + 0.15 * uname_fuzzy + 0.05 * name_fuzzy
        else:
            engage_fuzzy = transform_burstiness(engagement_score)
            uname_fuzzy = transform_burstiness(username_score)
            name_fuzzy = transform_burstiness(name_score)

            final = 0.4 * engage_fuzzy + 0.35 * uname_fuzzy + 0.25 * name_fuzzy

        profile["suspicious_score"] = {
            "temporal_entropy": temporal,
            "name_entropy": name_ent,
            "username_entropy": username_ent,
            "burstiness": bursts,
            "engagement_score": engagement_score,
            "final_score": final
        }

def generate_html(graph, explored_users, main_user, cache, suspicius_calc=False, followers_ratio=False):
    if suspicius_calc:
        allowed_nodes = {main_user} | set(graph.neighbors(main_user))
        subgraph = graph.subgraph(allowed_nodes).copy()
    else:
        isolated = [node for node in graph.nodes if node not in explored_users]
        subgraph = graph.copy()
        subgraph.remove_nodes_from(isolated)

    positions = nx.spring_layout(subgraph)
    for node in subgraph.nodes():
        subgraph.nodes[node].setdefault("count", 1)

    color_map = {}
    for node in subgraph.nodes():
        score = cache.get(node, {}).get("suspicious_score", {}).get("final_score", 0)
        if node == main_user:
            color_map[node] = "#6699cc"
        elif suspicius_calc and score >= 0.6:
            color_map[node] = "#FF0000" 
        elif node != main_user and subgraph.degree(node) == 1:
            color_map[node] = "#ffb6c1"
        elif main_user in list(subgraph.neighbors(node)):
            color_map[node] = "#75c793"
        else:
            color_map[node] = "#dddddd"

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

    # Save as SVG and create a minimal HTML wrapper instead of using mpld3
    svg_file = f"graph_{main_user}.svg"
    html_file = f"graph_{main_user}.html"
    try:
        fig.savefig(svg_file, format="svg", bbox_inches="tight")
        # Write a simple HTML file that embeds the SVG file
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

    # Open the generated HTML in the default browser
    try:
        webbrowser.open_new_tab(html_file)
    except Exception:
        pass