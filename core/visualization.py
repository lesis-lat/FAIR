import json
import webbrowser

from core.cache import load_graph, load_cache


def generate_html(social_graph, main_user, suspicious_calc=False, show_only_main_relations=True):
    graph = social_graph.graph
    cache = social_graph.cache

    all_nodes = set(graph.nodes())
    connected_nodes = set()
    for source_node_id, target_node_id in graph.edges():
        connected_nodes.add(source_node_id)
        connected_nodes.add(target_node_id)
    isolated_nodes = all_nodes - connected_nodes

    subgraph = graph.copy()
    if show_only_main_relations:
        allowed_nodes = {main_user}
        if graph.is_directed():
            predecessors = set()
            successors = set()
            if main_user in graph:
                predecessors = set(graph.predecessors(main_user))
                successors = set(graph.successors(main_user))
            allowed_nodes = {main_user} | predecessors | successors
        if not graph.is_directed():
            if main_user in graph:
                allowed_nodes = {main_user} | set(graph.neighbors(main_user))
            if main_user not in graph:
                allowed_nodes = {main_user}
        filtered_nodes = []
        for node in allowed_nodes:
            if node not in graph:
                continue
            filtered_nodes.append(node)
        allowed_nodes = filtered_nodes
        subgraph = graph.subgraph(allowed_nodes).copy()
    if not show_only_main_relations and suspicious_calc:
        allowed_nodes = {main_user} | set(graph.neighbors(main_user))
        subgraph = graph.subgraph(allowed_nodes).copy()

    nodes_data = []
    for node in subgraph.nodes():
        score = cache.get(node, {}).get("suspicious_score", {}).get("final_score", 0)
        is_isolated = node in isolated_nodes

        incoming_neighbors = set(subgraph.predecessors(node))
        outgoing_neighbors = set(subgraph.successors(node))
        has_main_connection = main_user in incoming_neighbors or main_user in outgoing_neighbors

        color = "#dddddd"
        if node == main_user:
            color = "#6699cc"
        if color == "#dddddd" and suspicious_calc and score >= 0.6:
            color = "#FF0000"
        if color == "#dddddd" and is_isolated:
            color = "#ffb6c1"
        if color == "#dddddd" and has_main_connection:
            color = "#75c793"

        interaction_type = "none"
        if incoming_neighbors and outgoing_neighbors:
            interaction_type = "bidirectional"
        if interaction_type == "none" and incoming_neighbors:
            interaction_type = "incoming"
        if interaction_type == "none" and outgoing_neighbors:
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
    for source, target, attributes in subgraph.edges(data=True):
        if "interactions" in attributes and attributes["interactions"]:
            interaction_types = [interaction["type"] for interaction in attributes["interactions"]]
            dominant_interaction = max(set(interaction_types), key=interaction_types.count)

            edge_color = {
                "comment": "#2ecc71",
                "mention": "#e74c3c",
                "tag": "#3498db",
            }.get(dominant_interaction, "gray")

            source_node = None
            target_node = None
            for node_data in nodes_data:
                if node_data["id"] == source:
                    source_node = node_data
                if node_data["id"] == target:
                    target_node = node_data

            if source_node and target_node:
                links_data.append(
                    {
                        "source": source,
                        "target": target,
                        "color": edge_color,
                        "width": min(attributes.get("weight", 1), 5),
                        "type": dominant_interaction,
                    }
                )

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

        data.links.forEach(linkData => {{
            linkData.source = data.nodes.find(nodeData => nodeData.id === linkData.source);
            linkData.target = data.nodes.find(nodeData => nodeData.id === linkData.target);
        }});

        const width = document.getElementById('graph').clientWidth;
        const height = document.getElementById('graph').clientHeight;

        const zoom = d3.zoom()
            .scaleExtent([0.1, 4])
            .on("zoom", zoomed);

        const svg = d3.select("#graph")
            .append("svg")
            .attr("width", width)
            .attr("height", height)
            .call(zoom);

        const container = svg.append("g");

        svg.append("defs").selectAll("marker")
            .data(["arrow"])
            .join("marker")
            .attr("id", markerId => markerId)
            .attr("viewBox", "0 -5 10 10")
            .attr("refX", 20)
            .attr("refY", 0)
            .attr("markerWidth", 6)
            .attr("markerHeight", 6)
            .attr("orient", "auto")
            .append("path")
            .attr("d", "M0,-5L10,0L0,5")
            .attr("class", "arrow-head");

        const tooltip = d3.select("body").append("div")
            .attr("class", "tooltip")
            .style("opacity", 0);

        const simulation = d3.forceSimulation(data.nodes)
            .force("link", d3.forceLink(data.links)
                .id(nodeData => nodeData.id)
                .distance(100))
            .force("charge", d3.forceManyBody()
                .strength(-1000)
                .distanceMax(500))
            .force("center", d3.forceCenter(width / 2, height / 2))
            .force("collide", d3.forceCollide().radius(nodeData => nodeData.size * 2));

        const links = container.append("g")
            .attr("class", "links")
            .selectAll("line")
            .data(data.links)
            .join("line")
            .attr("stroke", linkData => linkData.color)
            .attr("stroke-width", linkData => linkData.width)
            .attr("marker-end", "url(#arrow)")
            .attr("class", "link");

        const linkLabels = container.append("g")
            .attr("class", "link-labels")
            .selectAll("text")
            .data(data.links)
            .join("text")
            .attr("class", "link-label")
            .text(linkData => linkData.type)
            .attr("text-anchor", "middle")
            .attr("dy", -5)
            .style("font-size", "8px")
            .style("fill", linkData => linkData.color)
            .style("text-shadow", "1px 1px 2px white");

        const nodes = container.append("g")
            .selectAll("g")
            .data(data.nodes)
            .join("g")
            .call(d3.drag()
                .on("start", dragstarted)
                .on("drag", dragged)
                .on("end", dragended));

        nodes.append("circle")
            .attr("r", nodeData => nodeData.size)
            .attr("fill", nodeData => nodeData.color)
            .on("mouseover", showTooltip)
            .on("mouseout", hideTooltip);

        nodes.append("text")
            .text(nodeData => nodeData.label)
            .attr("text-anchor", "middle")
            .attr("dominant-baseline", "middle")
            .attr("y", nodeData => nodeData.size + 10)
            .style("font-size", "10px")
            .style("pointer-events", "none")
            .style("fill", "#000")
            .style("text-shadow", "0 0 3px white, 0 0 3px white, 0 0 3px white, 0 0 3px white");

        simulation.on("tick", () => {{
            links
                .attr("x1", linkData => linkData.source.x)
                .attr("y1", linkData => linkData.source.y)
                .attr("x2", linkData => linkData.target.x)
                .attr("y2", linkData => linkData.target.y);

            linkLabels
                .attr("x", linkData => (linkData.source.x + linkData.target.x) / 2)
                .attr("y", linkData => (linkData.source.y + linkData.target.y) / 2);

            nodes.attr("transform", nodeData => `translate(${{nodeData.x}},${{nodeData.y}})`);
        }});

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

        function filterNodes(type) {{
            const transition = d3.transition().duration(300);

            if (type === 'all') {{
                nodes.transition(transition).style("opacity", 1);
                links.transition(transition).style("opacity", 1);
                return;
            }}
            if (type === 'connected') {{
                nodes.transition(transition).style("opacity", nodeData => {{
                    if (nodeData.is_isolated) {{
                        return 0.1;
                    }}
                    return 1;
                }});
                links.transition(transition).style("opacity", 1);
                return;
            }}
            if (type === 'isolated') {{
                nodes.transition(transition).style("opacity", nodeData => {{
                    if (nodeData.is_isolated) {{
                        return 1;
                    }}
                    return 0.1;
                }});
                links.transition(transition).style("opacity", 0.1);
            }}
        }}

        function showTooltip(event, nodeData) {{
            let direction = "";
            if (nodeData.interaction_type !== "none") {{
                direction = `<br>Interaction: ${{nodeData.interaction_type}}`;
            }}

            tooltip.transition()
                .duration(200)
                .style("opacity", .9);
            tooltip.html(
                `<strong>${{nodeData.label}}</strong><br>` +
                `Followers: ${{nodeData.followers}}<br>` +
                `Following: ${{nodeData.following}}` +
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

    html_file = f"graph_{main_user}.html"
    with open(html_file, "w", encoding="utf-8") as f:
        f.write(html_content)

    try:
        webbrowser.open_new_tab(html_file)
    except Exception:
        pass


def generate_html_from_files(graph_path, cache_path, main_user, suspicious_calc=False, show_only_main_relations=True):
    graph = load_graph(graph_path)
    cache = load_cache(cache_path)

    class _Adapter:
        def __init__(self, graph, cache):
            self.graph = graph
            self.cache = cache

    social_graph = _Adapter(graph, cache)

    generate_html(
        social_graph,
        main_user,
        suspicious_calc=suspicious_calc,
        show_only_main_relations=show_only_main_relations,
    )
