import webbrowser
import json
from core.cache import load_graph, load_cache


def generate_html(social_graph, explored_users, main_user, suspicius_calc=False, show_only_main_relations=True):
    """Generate interactive HTML visualization using D3.js from an in-memory social_graph object.

    By default `show_only_main_relations=True` filters the visualization to include only
    the `main_user` and users that have at least one relation (incoming or outgoing)
    with the main user. Set to False to render the full graph.
    """
    graph = social_graph.graph
    cache = social_graph.cache

    # Get both connected and isolated nodes
    all_nodes = set(graph.nodes())
    connected_nodes = set()
    for u, v in graph.edges():
        connected_nodes.add(u)
        connected_nodes.add(v)
    isolated_nodes = all_nodes - connected_nodes

    # Prepare base subgraph
    if show_only_main_relations:
        # For directed graphs, consider both predecessors and successors to capture
        # any relation to the main user. For undirected graphs, neighbors() is sufficient.
        if graph.is_directed():
            preds = set(graph.predecessors(main_user)) if main_user in graph else set()
            succs = set(graph.successors(main_user)) if main_user in graph else set()
            allowed_nodes = {main_user} | preds | succs
        else:
            allowed_nodes = {main_user} | set(graph.neighbors(main_user)) if main_user in graph else {main_user}

        # Ensure allowed nodes exist in the graph
        allowed_nodes = [n for n in allowed_nodes if n in graph]
        subgraph = graph.subgraph(allowed_nodes).copy()
    elif suspicius_calc:
        allowed_nodes = {main_user} | set(graph.neighbors(main_user))
        subgraph = graph.subgraph(allowed_nodes).copy()
    else:
        subgraph = graph.copy()
        
    # Prepare nodes and links data
    nodes_data = []
    for node in subgraph.nodes():
        score = cache.get(node, {}).get("suspicious_score", {}).get("final_score", 0)
        is_isolated = node in isolated_nodes
        
        # Define node color
        color = "#6699cc" if node == main_user else \
                "#FF0000" if suspicius_calc and score >= 0.6 else \
                "#ffb6c1" if is_isolated else \
                "#75c793" if main_user in list(subgraph.predecessors(node)) or main_user in list(subgraph.successors(node)) else \
                "#dddddd"
        
        # Get interaction directions
        in_neighbors = list(subgraph.predecessors(node))
        out_neighbors = list(subgraph.successors(node))
        interaction_type = "none"
        if len(in_neighbors) > 0 and len(out_neighbors) > 0:
            interaction_type = "bidirectional"
        elif len(in_neighbors) > 0:
            interaction_type = "incoming"
        elif len(out_neighbors) > 0:
            interaction_type = "outgoing"
                
        nodes_data.append({
            "id": node,
            "label": f"{node}\n({subgraph.nodes[node].get('full_name', '')})",
            "color": color,
            "size": max(3, min(15, subgraph.nodes[node].get('count', 1) * 1.5)),
            "is_isolated": is_isolated,
            "interaction_type": interaction_type,
            "followers": cache.get(node, {}).get("followers", 0),
            "following": cache.get(node, {}).get("following", 0)
        })

    links_data = []
    for u, v, data in subgraph.edges(data=True):
        if 'interactions' in data and data['interactions']:
            interaction_types = [i['type'] for i in data['interactions']]
            most_common = max(set(interaction_types), key=interaction_types.count)
            
            edge_color = {
                'comment': '#2ecc71',
                'mention': '#e74c3c',
                'tag': '#3498db'
            }.get(most_common, 'gray')
            
            # Ensure we're using node objects instead of just IDs
            source_node = next((n for n in nodes_data if n["id"] == u), None)
            target_node = next((n for n in nodes_data if n["id"] == v), None)
            
            if source_node and target_node:
                links_data.append({
                    "source": u,
                    "target": v,
                    "color": edge_color,
                    "width": min(data.get('weight', 1), 5),
                    "type": most_common
                })

    html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Social Graph - {main_user}</title>
    <script src="https://d3js.org/d3.v7.min.js"></script>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600;700&display=swap" rel="stylesheet">
    <style>
        :root{{
            --bg: #f6f7fb;
            --card: #ffffff;
            --muted: #6b7280;
            --accent: #4f46e5;
            --accent-2: #06b6d4;
            --surface-shadow: 0 6px 18px rgba(15,23,42,0.06);
        }}
        html,body{{height:100%;}}
        body {{
            margin: 0;
            padding: 24px;
            font-family: 'Inter', system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial;
            background: linear-gradient(180deg, var(--bg), #ffffff);
            color: #0f172a;
            display: flex;
            justify-content: center;
            align-items: flex-start;
        }}
        .container {{
            width: 100%;
            max-width: 1200px;
        }}
        header{{display:flex;justify-content:space-between;align-items:center;gap:16px}}
        h1{{font-size:20px;margin:0;font-weight:600;color:#0b1220}}
        .meta{{color:var(--muted);font-size:13px}}
        .card{{background:var(--card);border-radius:12px;padding:14px;box-shadow:var(--surface-shadow);}}
        #graph-container{{height:72vh;min-height:480px;margin-top:18px;border-radius:12px;overflow:hidden}}
        #graph{{width:100%;height:100%;background:transparent}}
        .controls{{display:flex;gap:8px;align-items:center}}
        .controls .btn{{border-radius:8px}}
        .legend{{display:flex;flex-wrap:wrap;gap:10px;align-items:center}}
        .legend-item{{display:flex;align-items:center;gap:8px;color:var(--muted);font-size:13px}}
        .legend-dot{{width:14px;height:10px;border-radius:3px}}
        .tooltip{{position:absolute;padding:10px 12px;background:rgba(2,6,23,0.88);color:white;border-radius:8px;font-size:13px;pointer-events:none;box-shadow:0 6px 18px rgba(2,6,23,0.2);}}
        .link-label{{font-size:9px;font-weight:600}}
        .btn-ghost{{background:transparent;border:1px solid rgba(15,23,42,0.06);}}
        @media (max-width:700px){{
            h1{{font-size:16px}}
            .controls{{flex-wrap:wrap}}
        }}
        .arrow{{stroke-width:2;fill:none}}
        .arrow-head{{fill:currentColor}}
    </style>
</head>
<body>
    <div class="container">
        <h1 class="text-center mb-4">Social Graph for {main_user}</h1>
        
        <div class="controls">
            <div class="row">
                <div class="col-md-6">
                    <div class="btn-group" role="group">
                        <button class="btn btn-outline-primary" onclick="zoomIn()">
                            <i class="bi bi-zoom-in"></i> Zoom In
                        </button>
                        <button class="btn btn-outline-primary" onclick="zoomOut()">
                            <i class="bi bi-zoom-out"></i> Zoom Out
                        </button>
                        <button class="btn btn-outline-primary" onclick="resetZoom()">
                            <i class="bi bi-arrows-angle-contract"></i> Reset
                        </button>
                    </div>
                </div>
                <div class="col-md-6">
                    <div class="btn-group" role="group">
                        <button class="btn btn-outline-secondary" onclick="filterNodes('all')">All Nodes</button>
                        <button class="btn btn-outline-secondary" onclick="filterNodes('connected')">Connected Only</button>
                        <button class="btn btn-outline-secondary" onclick="filterNodes('isolated')">Isolated Only</button>
                    </div>
                </div>
            </div>
        </div>

        <div class="legend">
            <div class="legend-item">
                <div class="legend-color" style="background: #2ecc71;"></div>
                Comment
            </div>
            <div class="legend-item">
                <div class="legend-color" style="background: #e74c3c;"></div>
                Mention
            </div>
            <div class="legend-item">
                <div class="legend-color" style="background: #3498db;"></div>
                Tag
            </div>
            <div class="legend-item">
                <div class="legend-color" style="background: #6699cc;"></div>
                Main User
            </div>
            <div class="legend-item">
                <div class="legend-color" style="background: #ffb6c1;"></div>
                Isolated Profile
            </div>
        </div>

        <div id="graph-container">
            <div id="graph"></div>
        </div>
    </div>
    <script>
        let data = {{
            nodes: {json.dumps(nodes_data, ensure_ascii=False)},
            links: {json.dumps(links_data, ensure_ascii=False)}
        }};

        // Convert links source/target from id to node object references
        data.links.forEach(link => {{
            link.source = data.nodes.find(node => node.id === link.source);
            link.target = data.nodes.find(node => node.id === link.target);
        }});

        const width = document.getElementById('graph').clientWidth;
        const height = document.getElementById('graph').clientHeight;

        // Create zoom behavior
        const zoom = d3.zoom()
            .scaleExtent([0.1, 4])
            .on("zoom", zoomed);

        const svg = d3.select("#graph")
            .append("svg")
            .attr("width", width)
            .attr("height", height)
            .call(zoom);

        // Create a container for the graph that will be transformed by zoom
        const container = svg.append("g");

        // Create arrow markers for directed edges
        svg.append("defs").selectAll("marker")
            .data(["arrow"])
            .join("marker")
            .attr("id", d => d)
            .attr("viewBox", "0 -5 10 10")
            .attr("refX", 20)
            .attr("refY", 0)
            .attr("markerWidth", 6)
            .attr("markerHeight", 6)
            .attr("orient", "auto")
            .append("path")
            .attr("d", "M0,-5L10,0L0,5")
            .attr("class", "arrow-head");

        // Create tooltip
        const tooltip = d3.select("body").append("div")
            .attr("class", "tooltip")
            .style("opacity", 0);

        const simulation = d3.forceSimulation(data.nodes)
            .force("link", d3.forceLink(data.links)
                .id(d => d.id)
                .distance(100))
            .force("charge", d3.forceManyBody()
                .strength(-1000)
                .distanceMax(500))
            .force("center", d3.forceCenter(width / 2, height / 2))
            .force("collide", d3.forceCollide().radius(d => d.size * 2));

        // Create links with arrows
        const links = container.append("g")
            .attr("class", "links")
            .selectAll("line")
            .data(data.links)
            .join("line")
            .attr("stroke", d => d.color)
            .attr("stroke-width", d => d.width)
            .attr("marker-end", "url(#arrow)")
            .attr("class", "link");

        // Add interaction type labels to links
        const linkLabels = container.append("g")
            .attr("class", "link-labels")
            .selectAll("text")
            .data(data.links)
            .join("text")
            .attr("class", "link-label")
            .text(d => d.type)
            .attr("text-anchor", "middle")
            .attr("dy", -5)
            .style("font-size", "8px")
            .style("fill", d => d.color)
            .style("text-shadow", "1px 1px 2px white");

        // Create nodes
        const nodes = container.append("g")
            .selectAll("g")
            .data(data.nodes)
            .join("g")
            .call(d3.drag()
                .on("start", dragstarted)
                .on("drag", dragged)
                .on("end", dragended));

        nodes.append("circle")
            .attr("r", d => d.size)
            .attr("fill", d => d.color)
            .on("mouseover", showTooltip)
            .on("mouseout", hideTooltip);

        nodes.append("text")
            .text(d => d.label)
            .attr("text-anchor", "middle")
            .attr("dominant-baseline", "middle")
            .attr("y", d => d.size + 10)
            .style("font-size", "10px")
            .style("pointer-events", "none")
            .style("fill", "#000")
            .style("text-shadow", "0 0 3px white, 0 0 3px white, 0 0 3px white, 0 0 3px white");

        // Update simulation on tick
        simulation.on("tick", () => {{
            // Update link positions
            links
                .attr("x1", d => d.source.x)
                .attr("y1", d => d.source.y)
                .attr("x2", d => d.target.x)
                .attr("y2", d => d.target.y);

            // Update link label positions
            linkLabels
                .attr("x", d => (d.source.x + d.target.x) / 2)
                .attr("y", d => (d.source.y + d.target.y) / 2);

            // Update node positions
            nodes.attr("transform", d => `translate(${{d.x}},${{d.y}})`);
        }});

        // Zoom functions
        function zoomed(event) {{
            container.attr("transform", event.transform);
        }}

        function zoomIn() {{
            svg.transition().duration(500).call(zoom.scaleBy, 1.5);
        }}

        function zoomOut() {{
            svg.transition().duration(500).call(zoom.scaleBy, 0.67);
        }}

        function resetZoom() {{
            svg.transition().duration(500).call(zoom.transform, d3.zoomIdentity);
        }}

        // Node filtering
        function filterNodes(type) {{
            const t = d3.transition().duration(300);

            if (type === 'all') {{
                nodes.transition(t).style("opacity", 1);
                links.transition(t).style("opacity", 1);
            }} else if (type === 'connected') {{
                nodes.transition(t).style("opacity", d => d.is_isolated ? 0.1 : 1);
                links.transition(t).style("opacity", 1);
            }} else if (type === 'isolated') {{
                nodes.transition(t).style("opacity", d => d.is_isolated ? 1 : 0.1);
                links.transition(t).style("opacity", 0.1);
            }}
        }}

        // Tooltip functions
        function showTooltip(event, d) {{
            const direction = d.interaction_type !== "none" 
                ? `<br>Interaction: ${{d.interaction_type}}`
                : "";

            tooltip.transition()
                .duration(200)
                .style("opacity", .9);
            tooltip.html(
                `<strong>${{d.label}}</strong><br>` +
                `Followers: ${{d.followers}}<br>` +
                `Following: ${{d.following}}` +
                direction
            )
                .style("left", (event.pageX + 10) + "px")
                .style("top", (event.pageY - 10) + "px");
        }}

        function hideTooltip() {{
            tooltip.transition()
                .duration(500)
                .style("opacity", 0);
        }}

        // Drag functions
        function dragstarted(event) {{
            if (!event.active) simulation.alphaTarget(0.3).restart();
            event.subject.fx = event.subject.x;
            event.subject.fy = event.subject.y;
        }}

        function dragged(event) {{
            event.subject.fx = event.x;
            event.subject.fy = event.y;
        }}

        function dragended(event) {{
            if (!event.active) simulation.alphaTarget(0);
            event.subject.fx = null;
            event.subject.fy = null;
        }}
    </script>
</body>
</html>
"""

    # Save HTML file
    html_file = f"graph_{main_user}.html"
    with open(html_file, "w", encoding="utf-8") as f:
        f.write(html_content)

    # Open in browser
    try:
        webbrowser.open_new_tab(html_file)
    except Exception:
        pass


def generate_html_from_files(graph_path, cache_path, main_user, suspicius_calc=False, show_only_main_relations=True):
    """Load graph and cache from disk and generate the same HTML visualization.

    This is a convenience to build the HTML using the persisted graph file (graph.json)
    and the cache file (cache.json) without running the crawler again.
    """
    graph = load_graph(graph_path)
    cache = load_cache(cache_path)

    # reuse the same code path by creating a tiny adapter object
    class _Adapter:
        def __init__(self, graph, cache):
            self.graph = graph
            self.cache = cache

    social_graph = _Adapter(graph, cache)

    # We don't have the explored_users set here; build a set of nodes seen in cache
    explored_users = set(cache.keys())
    generate_html(social_graph, explored_users, main_user, suspicius_calc=suspicius_calc, show_only_main_relations=show_only_main_relations)
