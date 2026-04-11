package FAIR::Visualization;

use strict;
use warnings;
use Exporter 'import';
use Carp qw(croak);
use English qw(-no_match_vars);
use JSON::PP qw(encode_json);

use FAIR::Cache qw(
  load_graph
  load_cache
  graph_copy
  graph_subgraph
  graph_nodes
  graph_edges
  graph_successors
  graph_predecessors
  graph_neighbors
);

our @EXPORT_OK = qw(
  generate_html
  generate_html_from_files
);

our $VERSION = '0.1.0';

my $THREE = 1 + 2;
my $FIVE = 2 + 2 + 1;
my $FIFTEEN = (2 * 2 * 2) + (2 * 2) + (1 + 2);
my $SUSPICIOUS_SCORE_THRESHOLD = 1 - (2 / (2 + 2 + 1));
my $NODE_SIZE_MULTIPLIER = 1 + (1 / 2);

sub generate_html {
    my ($social_graph, $main_user, %opts) = @_;
    my $suspicious_calc = 0;
    if ($opts{suspicious_calc}) {
        $suspicious_calc = 1;
    }
    my $show_only_main_relations = 1;
    if (exists $opts{show_only_main_relations}) {
        $show_only_main_relations = 0;
        if ($opts{show_only_main_relations}) {
            $show_only_main_relations = 1;
        }
    }
    my $graph = $social_graph -> {graph};
    my $cache = $social_graph -> {cache} || {};
    my $subgraph = _select_subgraph(
        $graph,
        $main_user,
        $show_only_main_relations,
        $suspicious_calc,
    );
    my @nodes_data = _build_nodes_data(
        $subgraph,
        $cache,
        $main_user,
        $suspicious_calc,
    );
    my @links_data = _build_links_data($subgraph);
    my $nodes_json = encode_json(\@nodes_data);
    my $links_json = encode_json(\@links_data);
    my $has_relationship_data_json = 'false';
    if (@links_data) {
        $has_relationship_data_json = 'true';
    }
    my $html = _build_html_document(
        $main_user,
        $nodes_json,
        $links_json,
        $has_relationship_data_json,
    );
    my $html_file = "graph_${main_user}.html";
    _write_html_file($html_file, $html);
    return $html_file;
}

sub _select_subgraph {
    my ($graph, $main_user, $show_only_main_relations, $suspicious_calc) = @_;
    my $subgraph = graph_copy($graph);
    if ($show_only_main_relations) {
        my %allowed = ($main_user => 1);
        for my $user (graph_predecessors($graph, $main_user)) {
            $allowed{$user} = 1;
        }
        for my $user (graph_successors($graph, $main_user)) {
            $allowed{$user} = 1;
        }
        $subgraph = graph_subgraph($graph, [keys %allowed]);
        return $subgraph;
    }
    if ($suspicious_calc) {
        my %allowed = ($main_user => 1);
        for my $user (graph_neighbors($graph, $main_user)) {
            $allowed{$user} = 1;
        }
        $subgraph = graph_subgraph($graph, [keys %allowed]);
    }
    return $subgraph;
}

sub _build_nodes_data {
    my ($subgraph, $cache, $main_user, $suspicious_calc) = @_;
    my @nodes_data;
    for my $node (graph_nodes($subgraph)) {
        my $node_data = _build_single_node_data(
            $subgraph,
            $cache,
            $main_user,
            $suspicious_calc,
            $node,
        );
        push @nodes_data, $node_data;
    }
    if (!@nodes_data) {
        push @nodes_data, {
            id               => $main_user,
            label            => $main_user,
            color            => '#6699cc',
            size             => 8,
            is_isolated      => JSON::PP::true,
            interaction_type => 'none',
            followers        => $cache -> {$main_user}{followers} // 0,
            following        => $cache -> {$main_user}{following} // 0,
        };
    }
    return @nodes_data;
}

sub _build_single_node_data {
    my ($subgraph, $cache, $main_user, $suspicious_calc, $node) = @_;
    my $score = $cache -> {$node}{suspicious_score}{final_score} // 0;
    my @incoming_neighbors = graph_predecessors($subgraph, $node);
    my @outgoing_neighbors = graph_successors($subgraph, $node);
    my %neighbor_set = map { $_ => 1 } (@incoming_neighbors, @outgoing_neighbors);
    my $has_main_connection = 0;
    if (exists $neighbor_set{$main_user}) {
        $has_main_connection = 1;
    }
    my $is_isolated = 0;
    if (
        $node ne $main_user
        && scalar(keys %neighbor_set) == 1
        && $has_main_connection
    ) {
        $is_isolated = 1;
    }
    my $color = _node_color({
        node                => $node,
        main_user           => $main_user,
        suspicious_calc     => $suspicious_calc,
        score               => $score,
        is_isolated         => $is_isolated,
        has_main_connection => $has_main_connection,
    });
    my $interaction_type = _interaction_type(
        scalar(@incoming_neighbors),
        scalar(@outgoing_neighbors),
    );
    my $full_name = $subgraph -> {nodes}{$node}{full_name} // q{};
    my $label = $node;
    if ($full_name ne q{} && lc $full_name ne lc $node) {
        $label = "$node\n($full_name)";
    }
    my $count = $subgraph -> {nodes}{$node}{count} // 1;
    my $size = $count * $NODE_SIZE_MULTIPLIER;
    if ($size < $THREE) {
        $size = $THREE;
    }
    if ($size > $FIFTEEN) {
        $size = $FIFTEEN;
    }
    return {
        id               => $node,
        label            => $label,
        color            => $color,
        size             => $size,
        is_isolated      => _json_boolean($is_isolated),
        interaction_type => $interaction_type,
        followers        => $cache -> {$node}{followers} // 0,
        following        => $cache -> {$node}{following} // 0,
    };
}

sub _node_color {
    my ($args) = @_;
    my $node = $args -> {node};
    my $main_user = $args -> {main_user};
    my $suspicious_calc = $args -> {suspicious_calc};
    my $score = $args -> {score};
    my $is_isolated = $args -> {is_isolated};
    my $has_main_connection = $args -> {has_main_connection};

    if ($node eq $main_user) {
        return '#6699cc';
    }
    if ($suspicious_calc && $score >= $SUSPICIOUS_SCORE_THRESHOLD) {
        return '#FF0000';
    }
    if ($is_isolated) {
        return '#ffb6c1';
    }
    if ($has_main_connection) {
        return '#75c793';
    }
    return '#dddddd';
}

sub _interaction_type {
    my ($incoming_count, $outgoing_count) = @_;
    if ($incoming_count && $outgoing_count) {
        return 'bidirectional';
    }
    if ($incoming_count) {
        return 'incoming';
    }
    if ($outgoing_count) {
        return 'outgoing';
    }
    return 'none';
}

sub _build_links_data {
    my ($subgraph) = @_;
    my @links_data;
    for my $edge (graph_edges($subgraph)) {
        my ($source, $target, $attributes) = @{$edge};
        my $interactions = $attributes -> {interactions};
        if (ref($interactions) ne 'ARRAY' || !@{$interactions}) {
            next;
        }
        my %types;
        for my $interaction (@{$interactions}) {
            my $type = $interaction -> {type} // 'unknown';
            $types{$type}++;
        }
        my @sorted_types = sort {
            ($types{$a} <=> $types{$b}) || ($a cmp $b)
        } keys %types;
        my $dominant_type = $sorted_types[-1];
        my $edge_color = {
            comment => '#2ecc71',
            mention => '#e74c3c',
            tag     => '#3498db',
        } -> {$dominant_type} // 'gray';
        my $weight = $attributes -> {weight} // 1;
        if ($weight > $FIVE) {
            $weight = $FIVE;
        }
        push @links_data, {
            source => $source,
            target => $target,
            color  => $edge_color,
            width  => $weight,
            type   => $dominant_type,
        };
    }
    return @links_data;
}

sub _build_html_document {
    my (
        $main_user,
        $nodes_json,
        $links_json,
        $has_relationship_data_json,
    ) = @_;
    my $html = <<'HTML';
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Social Graph - __MAIN_USER__</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&display=swap" rel="stylesheet">
  <script src="https://d3js.org/d3.v7.min.js"></script>
  <style>
    :root {
      --bg-0: #0a0c10;
      --bg-1: #10141b;
      --bg-2: #151b24;
      --panel: rgba(17, 22, 30, 0.86);
      --line: rgba(255, 255, 255, 0.08);
      --ink: #e8edf7;
      --muted: #98a2b3;
      --accent: #7dd3fc;
      --accent-2: #38bdf8;
    }
    * {
      box-sizing: border-box;
    }
    body {
      margin: 0;
      padding: 28px;
      font-family: "Space Grotesk", "Segoe UI", Arial, sans-serif;
      background:
        radial-gradient(1200px 600px at -10% -20%, #142034 0%, transparent 65%),
        radial-gradient(900px 500px at 115% 0%, #1e293b 0%, transparent 60%),
        linear-gradient(180deg, var(--bg-0), var(--bg-1) 35%, var(--bg-2));
      color: var(--ink);
      min-height: 100vh;
    }
    .wrap {
      max-width: 1280px;
      margin: 0 auto;
    }
    .header {
      display: flex;
      align-items: flex-end;
      justify-content: space-between;
      gap: 16px;
      background: var(--panel);
      border-radius: 18px;
      border: 1px solid var(--line);
      box-shadow: 0 24px 54px rgba(0, 0, 0, 0.35);
      backdrop-filter: blur(6px);
      padding: 16px 20px;
      margin-bottom: 14px;
    }
    h1 {
      margin: 0;
      font-size: 25px;
      font-weight: 600;
      letter-spacing: 0.01em;
    }
    .meta {
      color: var(--muted);
      font-size: 12px;
      margin-top: 6px;
      text-transform: uppercase;
      letter-spacing: 0.08em;
    }
    .stats {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      justify-content: flex-end;
    }
    .pill {
      border: 1px solid var(--line);
      color: var(--ink);
      background: rgba(255, 255, 255, 0.03);
      border-radius: 999px;
      padding: 8px 12px;
      font-size: 12px;
      font-weight: 500;
      white-space: nowrap;
    }
    #graph-container {
      width: 100%;
      height: 78vh;
      min-height: 560px;
      overflow: hidden;
      border-radius: 18px;
      border: 1px solid var(--line);
      background:
        radial-gradient(900px 400px at 80% -10%, rgba(56, 189, 248, 0.08), transparent 65%),
        radial-gradient(1100px 500px at 10% 120%, rgba(14, 116, 144, 0.1), transparent 65%),
        rgba(8, 10, 14, 0.92);
      box-shadow: 0 24px 54px rgba(0, 0, 0, 0.4);
      position: relative;
    }
    #graph {
      width: 100%;
      height: 100%;
    }
    .legend {
      position: absolute;
      right: 16px;
      bottom: 16px;
      display: flex;
      flex-direction: column;
      gap: 8px;
      background: rgba(10, 14, 20, 0.78);
      border: 1px solid var(--line);
      border-radius: 12px;
      padding: 10px 12px;
      backdrop-filter: blur(6px);
      z-index: 2;
      pointer-events: none;
    }
    .legend-row {
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 11px;
      color: var(--muted);
      letter-spacing: 0.03em;
      text-transform: uppercase;
    }
    .legend-dot {
      width: 9px;
      height: 9px;
      border-radius: 999px;
      flex: 0 0 auto;
    }
    .tooltip {
      position: absolute;
      pointer-events: none;
      background: rgba(6, 9, 12, 0.95);
      border: 1px solid rgba(125, 211, 252, 0.25);
      color: var(--ink);
      padding: 10px 12px;
      border-radius: 12px;
      font-size: 12px;
      opacity: 0;
      transition: opacity 180ms ease, transform 180ms ease;
      transform: translateY(4px);
      box-shadow: 0 14px 30px rgba(0, 0, 0, 0.45);
      max-width: 280px;
    }
    .empty-state {
      margin-top: 10px;
      color: var(--muted);
      font-size: 12px;
      letter-spacing: 0.02em;
    }
    @media (max-width: 780px) {
      body {
        padding: 14px;
      }
      .header {
        padding: 14px;
        flex-direction: column;
        align-items: flex-start;
      }
      .stats {
        justify-content: flex-start;
      }
      #graph-container {
        min-height: 500px;
      }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="header">
      <div>
      <h1>Activity Map for @__MAIN_USER__</h1>
      <div class="meta">FAIR interactive graph</div>
      <div class="empty-state" id="empty-state"></div>
      </div>
      <div class="stats">
        <div class="pill" id="stat-nodes">Nodes: 0</div>
        <div class="pill" id="stat-links">Edges: 0</div>
        <div class="pill" id="stat-has-data">Data: no</div>
      </div>
    </div>
    <div id="graph-container">
      <div class="legend">
        <div class="legend-row">
          <span class="legend-dot" style="background:#2ecc71"></span>
          <span>Comment</span>
        </div>
        <div class="legend-row">
          <span class="legend-dot" style="background:#e74c3c"></span>
          <span>Mention</span>
        </div>
        <div class="legend-row">
          <span class="legend-dot" style="background:#3498db"></span>
          <span>Tag</span>
        </div>
      </div>
      <div id="graph"></div>
    </div>
  </div>
  <div class="tooltip" id="tooltip"></div>
  <script>
    const data = {
      nodes: __NODES_JSON__,
      links: __LINKS_JSON__
    };
    const hasRelationshipData = __HAS_RELATIONSHIP_DATA__;
    const emptyState = document.getElementById('empty-state');
    const statNodes = document.getElementById('stat-nodes');
    const statLinks = document.getElementById('stat-links');
    const statHasData = document.getElementById('stat-has-data');

    statNodes.textContent = `Nodes: ${data.nodes.length}`;
    statLinks.textContent = `Edges: ${data.links.length}`;
    if (hasRelationshipData) {
      statHasData.textContent = 'Data: yes';
    }
    if (!hasRelationshipData) {
      statHasData.textContent = 'Data: no';
    }

    if (typeof d3 === 'undefined') {
      emptyState.textContent = 'Graph library could not be loaded. Check your internet connection and reload this file.';
      throw new Error('d3 not loaded');
    }

    if (!hasRelationshipData) {
      emptyState.textContent = 'No interactions were fetched for this user. Showing a fallback node only.';
    }

    const nodeIds = new Set(data.nodes.map(n => n.id));
    data.links = data.links.filter(link =>
      nodeIds.has(link.source) && nodeIds.has(link.target)
    );

    data.links.forEach(link => {
      link.source = data.nodes.find(n => n.id === link.source);
      link.target = data.nodes.find(n => n.id === link.target);
    });

    const width = document.getElementById('graph').clientWidth;
    const height = document.getElementById('graph').clientHeight;

    const zoom = d3.zoom().scaleExtent([0.1, 4]).on('zoom', (event) => {
      container.attr('transform', event.transform);
    });

    const svg = d3.select('#graph').append('svg')
      .attr('width', width)
      .attr('height', height)
      .call(zoom);

    const container = svg.append('g');

    svg.append('defs').append('marker')
      .attr('id', 'arrow')
      .attr('viewBox', '0 -5 10 10')
      .attr('refX', 20)
      .attr('refY', 0)
      .attr('markerWidth', 6)
      .attr('markerHeight', 6)
      .attr('orient', 'auto')
      .append('path')
      .attr('d', 'M0,-5L10,0L0,5')
      .attr('fill', 'rgba(152, 162, 179, 0.8)');

    const tooltip = d3.select('#tooltip');

    const simulation = d3.forceSimulation(data.nodes)
      .force('link', d3.forceLink(data.links).id(d => d.id).distance(100))
      .force('charge', d3.forceManyBody().strength(-1000).distanceMax(500))
      .force('center', d3.forceCenter(width / 2, height / 2))
      .force('collide', d3.forceCollide().radius(d => d.size * 2));

    const links = container.append('g')
      .selectAll('line')
      .data(data.links)
      .join('line')
      .attr('stroke', d => d.color)
      .attr('stroke-width', d => d.width)
      .attr('stroke-opacity', 0.65)
      .attr('marker-end', 'url(#arrow)');

    const nodes = container.append('g')
      .selectAll('g')
      .data(data.nodes)
      .join('g')
      .call(d3.drag()
        .on('start', dragstarted)
        .on('drag', dragged)
        .on('end', dragended));

    nodes.append('circle')
      .attr('r', d => d.size)
      .attr('fill', d => d.color)
      .attr('stroke', 'rgba(232, 237, 247, 0.34)')
      .attr('stroke-width', 1)
      .on('mouseover', (event, d) => {
        tooltip.style('opacity', 1)
          .style('transform', 'translateY(0)')
          .html(`<strong>${d.label}</strong><br>Followers: ${d.followers}<br>Following: ${d.following}`)
          .style('left', (event.pageX + 10) + 'px')
          .style('top', (event.pageY - 10) + 'px');
      })
      .on('mouseout', () => {
        tooltip.style('opacity', 0)
          .style('transform', 'translateY(4px)');
      });

    nodes.append('text')
      .text(d => d.label)
      .attr('text-anchor', 'middle')
      .attr('y', d => d.size + 10)
      .style('font-size', '10px')
      .style('fill', '#cbd5e1')
      .style('font-weight', '500')
      .style('pointer-events', 'none');

    simulation.on('tick', () => {
      links
        .attr('x1', d => d.source.x)
        .attr('y1', d => d.source.y)
        .attr('x2', d => d.target.x)
        .attr('y2', d => d.target.y);

      nodes.attr('transform', d => `translate(${d.x},${d.y})`);
    });

    function dragstarted(event) {
      if (!event.active) simulation.alphaTarget(0.3).restart();
      event.subject.fx = event.subject.x;
      event.subject.fy = event.subject.y;
    }

    function dragged(event) {
      event.subject.fx = event.x;
      event.subject.fy = event.y;
    }

    function dragended(event) {
      if (!event.active) simulation.alphaTarget(0);
      event.subject.fx = null;
      event.subject.fy = null;
    }
  </script>
</body>
</html>
HTML

    $html =~ s/__MAIN_USER__/$main_user/gxms;
    $html =~ s/__NODES_JSON__/$nodes_json/gxms;
    $html =~ s/__LINKS_JSON__/$links_json/gxms;
    $html =~ s/__HAS_RELATIONSHIP_DATA__/$has_relationship_data_json/gxms;
    return $html;
}

sub _write_html_file {
    my ($html_file, $html) = @_;
    open my $fh, '>:encoding(UTF-8)', $html_file
      or croak "Cannot write $html_file: $OS_ERROR";
    print {$fh} $html;
    close $fh or croak "Cannot close $html_file: $OS_ERROR";
    return;
}

sub _json_boolean {
    my ($value) = @_;
    if ($value) {
        return JSON::PP::true;
    }
    return JSON::PP::false;
}

sub generate_html_from_files {
    my ($graph_path, $cache_path, $main_user, %opts) = @_;

    my $graph = load_graph($graph_path);
    my $cache = load_cache($cache_path);

    my $social_graph = {
        graph => $graph,
        cache => $cache,
    };

    return generate_html($social_graph, $main_user, %opts);
}

1;
