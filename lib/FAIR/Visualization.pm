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
    my $cache_meta = {};
    if (ref($cache -> {$node}{cache_meta}) eq 'HASH') {
        $cache_meta = $cache -> {$node}{cache_meta};
    }
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
        suspicious_score => $score,
        profile_cached_at => $cache_meta -> {profile_cached_at} // q{},
        profile_expires_at => $cache_meta -> {profile_expires_at} // q{},
        posts_cached_at => $cache_meta -> {posts_cached_at} // q{},
        posts_expires_at => $cache_meta -> {posts_expires_at} // q{},
        cache_source => $cache_meta -> {last_source} // q{},
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
        my $interaction_count = scalar @{$interactions};
        my $last_interaction = q{};
        for my $interaction (@{$interactions}) {
            my $timestamp = $interaction -> {timestamp};
            if (!defined $timestamp || $timestamp eq q{}) {
                $timestamp = $interaction -> {created_at};
            }
            if (!defined $timestamp || $timestamp eq q{}) {
                $timestamp = $interaction -> {taken_at};
            }
            if (!defined $timestamp || $timestamp eq q{}) {
                $timestamp = $interaction -> {date};
            }
            if (!defined $timestamp || $timestamp eq q{}) {
                next;
            }
            if ($last_interaction eq q{} || $timestamp gt $last_interaction) {
                $last_interaction = $timestamp;
            }
        }
        push @links_data, {
            source            => $source,
            target            => $target,
            color             => $edge_color,
            width             => $weight,
            type              => $dominant_type,
            interaction_count => $interaction_count,
            last_interaction  => $last_interaction,
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
    .controls {
      display: grid;
      grid-template-columns: 1fr auto;
      gap: 12px;
      background: var(--panel);
      border-radius: 18px;
      border: 1px solid var(--line);
      box-shadow: 0 24px 54px rgba(0, 0, 0, 0.35);
      backdrop-filter: blur(6px);
      padding: 14px 16px;
      margin-bottom: 14px;
    }
    .control-row {
      display: flex;
      flex-wrap: wrap;
      gap: 8px 12px;
      align-items: center;
    }
    .control {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      border: 1px solid var(--line);
      border-radius: 10px;
      padding: 7px 10px;
      background: rgba(255, 255, 255, 0.03);
      font-size: 12px;
      color: var(--muted);
    }
    .control input[type="text"] {
      width: 180px;
      background: transparent;
      border: none;
      color: var(--ink);
      outline: none;
      font-family: inherit;
      font-size: 12px;
    }
    .control input[type="range"] {
      width: 132px;
      accent-color: var(--accent-2);
    }
    .control label {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      cursor: pointer;
      user-select: none;
    }
    .control button {
      border: 1px solid var(--line);
      background: rgba(255, 255, 255, 0.04);
      color: var(--ink);
      border-radius: 8px;
      padding: 5px 8px;
      font-family: inherit;
      font-size: 11px;
      cursor: pointer;
    }
    .control button:hover {
      border-color: rgba(125, 211, 252, 0.35);
      background: rgba(125, 211, 252, 0.1);
    }
    .actions {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      justify-content: flex-end;
    }
    .action {
      border: 1px solid var(--line);
      border-radius: 10px;
      padding: 8px 11px;
      color: var(--ink);
      background: rgba(255, 255, 255, 0.03);
      font-size: 12px;
      font-weight: 500;
      cursor: pointer;
    }
    .action:hover {
      border-color: rgba(125, 211, 252, 0.45);
      background: rgba(125, 211, 252, 0.12);
    }
    .action:focus-visible {
      outline: 2px solid var(--accent);
      outline-offset: 2px;
    }
    .timeline {
      display: inline-flex;
      align-items: center;
      gap: 8px;
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
    #graph svg {
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
    .inspector {
      position: absolute;
      top: 16px;
      right: 16px;
      width: 280px;
      max-width: calc(100% - 32px);
      background: rgba(10, 14, 20, 0.82);
      border: 1px solid var(--line);
      border-radius: 12px;
      padding: 12px;
      backdrop-filter: blur(6px);
      z-index: 3;
      box-shadow: 0 14px 30px rgba(0, 0, 0, 0.38);
    }
    .inspector-title {
      margin: 0;
      font-size: 11px;
      color: var(--muted);
      letter-spacing: 0.08em;
      text-transform: uppercase;
      font-weight: 600;
    }
    .inspector-name {
      margin-top: 6px;
      font-size: 14px;
      font-weight: 600;
      color: var(--ink);
      word-break: break-word;
    }
    .inspector-grid {
      margin-top: 10px;
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 6px;
    }
    .inspector-item {
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 6px 8px;
      background: rgba(255, 255, 255, 0.03);
    }
    .inspector-label {
      display: block;
      font-size: 10px;
      color: var(--muted);
      text-transform: uppercase;
      letter-spacing: 0.06em;
    }
    .inspector-value {
      display: block;
      margin-top: 4px;
      font-size: 12px;
      color: var(--ink);
      font-weight: 600;
    }
    .inspector-status {
      margin-top: 10px;
      font-size: 11px;
      color: var(--muted);
    }
    .shortcuts {
      margin-top: 8px;
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
    }
    .keycap {
      border: 1px solid var(--line);
      border-radius: 6px;
      padding: 4px 6px;
      font-size: 10px;
      color: var(--ink);
      background: rgba(255, 255, 255, 0.03);
      line-height: 1;
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
    .focus-banner {
      margin-top: 8px;
      font-size: 12px;
      color: var(--accent);
      min-height: 16px;
    }
    .high-contrast {
      --bg-0: #000000;
      --bg-1: #090a0d;
      --bg-2: #111318;
      --line: rgba(255, 255, 255, 0.22);
      --ink: #ffffff;
      --muted: #d4d7df;
      --accent: #93e9ff;
      --accent-2: #5edbff;
    }
    .reduced-motion * {
      transition: none !important;
      animation: none !important;
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
      .controls {
        grid-template-columns: 1fr;
      }
      .actions {
        justify-content: flex-start;
      }
      #graph-container {
        min-height: 500px;
      }
      .inspector {
        position: absolute;
        left: 14px;
        right: 14px;
        width: auto;
      }
      .legend {
        left: 14px;
        right: auto;
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
      <div class="focus-banner" id="focus-banner"></div>
      </div>
      <div class="stats">
        <div class="pill" id="stat-nodes">Nodes: 0</div>
        <div class="pill" id="stat-links">Edges: 0</div>
        <div class="pill" id="stat-has-data">Data: no</div>
      </div>
    </div>
    <div class="controls">
      <div class="control-row">
        <div class="control">
          <span>Search</span>
          <input id="search-input" type="text" placeholder="username" aria-label="Search node">
        </div>
        <div class="control">
          <span>Edge type</span>
          <label><input id="filter-comment" type="checkbox" checked>comment</label>
          <label><input id="filter-mention" type="checkbox" checked>mention</label>
          <label><input id="filter-tag" type="checkbox" checked>tag</label>
        </div>
        <div class="control">
          <span>Min score</span>
          <input id="min-score" type="range" min="0" max="1" step="0.01" value="0">
          <span id="min-score-value">0.00</span>
        </div>
        <div class="control">
          <label><input id="focus-mode" type="checkbox" checked>focus mode</label>
          <label><input id="cluster-mode" type="checkbox">collapse clusters</label>
          <label><input id="timeline-mode" type="checkbox">timeline</label>
        </div>
        <div class="control timeline">
          <button id="timeline-play" type="button">Play</button>
          <input id="timeline-progress" type="range" min="0" max="100" step="1" value="100">
          <span id="timeline-label">100%</span>
        </div>
      </div>
      <div class="actions">
        <button class="action" id="reset-layout" type="button">Reset</button>
        <button class="action" id="clear-focus" type="button">Clear Focus</button>
        <button class="action" id="fit-view" type="button">Fit</button>
        <button class="action" id="toggle-contrast" type="button">Contrast</button>
        <button class="action" id="toggle-motion" type="button">Motion</button>
        <button class="action" id="export-png" type="button">PNG</button>
        <button class="action" id="export-svg" type="button">SVG</button>
        <button class="action" id="export-json" type="button">JSON</button>
        <button class="action" id="export-csv" type="button">CSV</button>
      </div>
    </div>
    <div id="graph-container">
      <aside class="inspector" aria-live="polite">
        <h2 class="inspector-title">Selection</h2>
        <div class="inspector-name" id="inspector-name">@__MAIN_USER__</div>
        <div class="inspector-grid">
          <div class="inspector-item">
            <span class="inspector-label">Risk Score</span>
            <span class="inspector-value" id="inspector-score">0.00</span>
          </div>
          <div class="inspector-item">
            <span class="inspector-label">Followers</span>
            <span class="inspector-value" id="inspector-followers">0</span>
          </div>
          <div class="inspector-item">
            <span class="inspector-label">Following</span>
            <span class="inspector-value" id="inspector-following">0</span>
          </div>
          <div class="inspector-item">
            <span class="inspector-label">Connections</span>
            <span class="inspector-value" id="inspector-connections">0</span>
          </div>
        </div>
        <div class="inspector-status" id="inspector-status">Click a node to inspect it.</div>
        <div class="shortcuts" id="shortcuts-row">
          <span class="keycap">/ search</span>
          <span class="keycap">Esc clear</span>
          <span class="keycap">← → focus</span>
          <span class="keycap">F fit</span>
        </div>
      </aside>
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
    const mainUser = '__MAIN_USER__';
    const data = {
      nodes: __NODES_JSON__,
      links: __LINKS_JSON__
    };
    const hasRelationshipData = __HAS_RELATIONSHIP_DATA__;
    const emptyState = document.getElementById('empty-state');
    const focusBanner = document.getElementById('focus-banner');
    const statNodes = document.getElementById('stat-nodes');
    const statLinks = document.getElementById('stat-links');
    const statHasData = document.getElementById('stat-has-data');
    const searchInput = document.getElementById('search-input');
    const minScoreInput = document.getElementById('min-score');
    const minScoreValue = document.getElementById('min-score-value');
    const filterComment = document.getElementById('filter-comment');
    const filterMention = document.getElementById('filter-mention');
    const filterTag = document.getElementById('filter-tag');
    const focusModeInput = document.getElementById('focus-mode');
    const clusterModeInput = document.getElementById('cluster-mode');
    const timelineModeInput = document.getElementById('timeline-mode');
    const timelinePlayButton = document.getElementById('timeline-play');
    const timelineProgressInput = document.getElementById('timeline-progress');
    const timelineLabel = document.getElementById('timeline-label');
    const resetLayoutButton = document.getElementById('reset-layout');
    const clearFocusButton = document.getElementById('clear-focus');
    const fitViewButton = document.getElementById('fit-view');
    const toggleContrastButton = document.getElementById('toggle-contrast');
    const toggleMotionButton = document.getElementById('toggle-motion');
    const exportPngButton = document.getElementById('export-png');
    const exportSvgButton = document.getElementById('export-svg');
    const exportJsonButton = document.getElementById('export-json');
    const exportCsvButton = document.getElementById('export-csv');
    const graphContainer = document.getElementById('graph-container');
    const graphRoot = document.getElementById('graph');
    const inspectorName = document.getElementById('inspector-name');
    const inspectorScore = document.getElementById('inspector-score');
    const inspectorFollowers = document.getElementById('inspector-followers');
    const inspectorFollowing = document.getElementById('inspector-following');
    const inspectorConnections = document.getElementById('inspector-connections');
    const inspectorStatus = document.getElementById('inspector-status');

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

    const nodeIds = new Set(data.nodes.map((node) => node.id));
    const sourceLinks = data.links
      .filter((link) => nodeIds.has(link.source) && nodeIds.has(link.target))
      .map((link, index) => {
        const parsedTime = parseTimeValue(link.last_interaction);
        return {
          source: link.source,
          target: link.target,
          color: link.color,
          width: Number(link.width) || 1,
          type: link.type || 'unknown',
          interaction_count: Number(link.interaction_count) || 0,
          last_interaction: link.last_interaction || '',
          parsed_time: parsedTime,
          fallback_time: index + 1
        };
      });
    const sourceNodes = data.nodes.map((node) => ({
      ...node,
      label_short: String(node.id || ''),
      suspicious_score: Number(node.suspicious_score) || 0,
      followers: Number(node.followers) || 0,
      following: Number(node.following) || 0
    }));
    const adjacency = buildAdjacency(sourceNodes, sourceLinks);
    const state = {
      search: '',
      minScore: 0,
      edgeTypes: new Set(['comment', 'mention', 'tag']),
      focusMode: true,
      focusedId: mainUser,
      clusterMode: false,
      timelineMode: false,
      timelineValue: 1,
      timelineRunning: false,
      highContrast: false,
      reducedMotion: window.matchMedia('(prefers-reduced-motion: reduce)').matches,
      zoomLevel: 1,
      selectedId: mainUser
    };
    const tooltip = d3.select('#tooltip');
    let svg = null;
    let container = null;
    let simulation = null;
    let zoomBehavior = null;
    let zoomTransform = d3.zoomIdentity;
    let renderedNodes = [];
    let renderedLinks = [];
    let timelineTimer = null;
    let pendingViewportTimer = null;
    initialize();

    function initialize() {
      if (!sourceNodes.some((node) => node.id === mainUser)) {
        state.focusedId = null;
        state.selectedId = null;
      }
      if (!sourceNodes.some((node) => node.id === state.selectedId)) {
        state.selectedId = sourceNodes.length > 0 ? sourceNodes[0].id : null;
      }
      if (state.reducedMotion) {
        document.body.classList.add('reduced-motion');
      }
      wireControls();
      renderGraph();
    }

    function wireControls() {
      searchInput.addEventListener('input', () => {
        state.search = searchInput.value.trim().toLowerCase();
        renderGraph();
      });
      minScoreInput.addEventListener('input', () => {
        state.minScore = Number(minScoreInput.value);
        minScoreValue.textContent = state.minScore.toFixed(2);
        renderGraph();
      });
      filterComment.addEventListener('change', updateEdgeFilters);
      filterMention.addEventListener('change', updateEdgeFilters);
      filterTag.addEventListener('change', updateEdgeFilters);
      focusModeInput.addEventListener('change', () => {
        state.focusMode = focusModeInput.checked;
        if (!state.focusMode) {
          state.focusedId = null;
        }
        renderGraph();
      });
      clusterModeInput.addEventListener('change', () => {
        state.clusterMode = clusterModeInput.checked;
        renderGraph();
      });
      timelineModeInput.addEventListener('change', () => {
        state.timelineMode = timelineModeInput.checked;
        if (!state.timelineMode) {
          state.timelineRunning = false;
          timelinePlayButton.textContent = 'Play';
          stopTimeline();
        }
        renderGraph();
      });
      timelinePlayButton.addEventListener('click', () => {
        if (!state.timelineMode) {
          state.timelineMode = true;
          timelineModeInput.checked = true;
        }
        if (state.timelineRunning) {
          state.timelineRunning = false;
          timelinePlayButton.textContent = 'Play';
          stopTimeline();
          return;
        }
        state.timelineRunning = true;
        timelinePlayButton.textContent = 'Pause';
        runTimeline();
      });
      timelineProgressInput.addEventListener('input', () => {
        state.timelineValue = Number(timelineProgressInput.value) / 100;
        updateTimelineLabel();
        renderGraph();
      });
      resetLayoutButton.addEventListener('click', () => {
        if (state.focusMode) {
          state.focusedId = mainUser;
        }
        if (!state.focusMode) {
          state.focusedId = null;
        }
        renderGraph();
      });
      clearFocusButton.addEventListener('click', () => {
        state.focusedId = null;
        renderGraph();
      });
      fitViewButton.addEventListener('click', fitToView);
      toggleContrastButton.addEventListener('click', () => {
        state.highContrast = !state.highContrast;
        if (state.highContrast) {
          document.body.classList.add('high-contrast');
        }
        if (!state.highContrast) {
          document.body.classList.remove('high-contrast');
        }
      });
      toggleMotionButton.addEventListener('click', () => {
        state.reducedMotion = !state.reducedMotion;
        if (state.reducedMotion) {
          document.body.classList.add('reduced-motion');
        }
        if (!state.reducedMotion) {
          document.body.classList.remove('reduced-motion');
        }
      });
      exportSvgButton.addEventListener('click', exportSvg);
      exportPngButton.addEventListener('click', exportPng);
      exportJsonButton.addEventListener('click', exportJson);
      exportCsvButton.addEventListener('click', exportCsv);
      window.addEventListener('resize', renderGraph);
      window.addEventListener('keydown', handleKeyboardShortcuts);
      minScoreValue.textContent = Number(minScoreInput.value).toFixed(2);
      updateTimelineLabel();
    }

    function updateEdgeFilters() {
      const nextSet = new Set();
      if (filterComment.checked) {
        nextSet.add('comment');
      }
      if (filterMention.checked) {
        nextSet.add('mention');
      }
      if (filterTag.checked) {
        nextSet.add('tag');
      }
      state.edgeTypes = nextSet;
      renderGraph();
    }

    function runTimeline() {
      stopTimeline();
      timelineTimer = window.setInterval(() => {
        let nextValue = Math.round(state.timelineValue * 100) + 4;
        if (nextValue > 100) {
          nextValue = 0;
        }
        timelineProgressInput.value = String(nextValue);
        state.timelineValue = nextValue / 100;
        updateTimelineLabel();
        renderGraph();
      }, 420);
    }

    function stopTimeline() {
      if (timelineTimer !== null) {
        window.clearInterval(timelineTimer);
        timelineTimer = null;
      }
    }

    function updateTimelineLabel() {
      timelineLabel.textContent = `${Math.round(state.timelineValue * 100)}%`;
    }

    async function renderGraph() {
      const renderData = buildRenderData();
      renderedNodes = renderData.nodes;
      renderedLinks = renderData.links;
      syncSelectionWithRenderedGraph();
      statNodes.textContent = `Nodes: ${renderedNodes.length}`;
      statLinks.textContent = `Edges: ${renderedLinks.length}`;
      await renderD3(renderData);
      updateFocusBanner();
      updateInspector();
    }

    function syncSelectionWithRenderedGraph() {
      if (renderedNodes.length === 0) {
        state.selectedId = null;
        return;
      }
      const hasCurrentSelection = renderedNodes.some((node) => node.id === state.selectedId);
      if (hasCurrentSelection) {
        return;
      }
      if (state.focusedId && renderedNodes.some((node) => node.id === state.focusedId)) {
        state.selectedId = state.focusedId;
        return;
      }
      state.selectedId = renderedNodes[0].id;
    }

    function buildRenderData() {
      const baseNodes = sourceNodes.filter((node) => {
        if (node.suspicious_score < state.minScore) {
          return false;
        }
        return true;
      });
      const baseNodeIds = new Set(baseNodes.map((node) => node.id));
      const filteredLinks = sourceLinks.filter((link) => {
        if (!baseNodeIds.has(link.source) || !baseNodeIds.has(link.target)) {
          return false;
        }
        if (!state.edgeTypes.has(link.type)) {
          return false;
        }
        if (!state.timelineMode) {
          return true;
        }
        const normalizedTime = normalizeLinkTime(link);
        if (normalizedTime <= state.timelineValue) {
          return true;
        }
        return false;
      });
      const connectedIds = new Set();
      for (const link of filteredLinks) {
        connectedIds.add(link.source);
        connectedIds.add(link.target);
      }
      for (const node of baseNodes) {
        if (node.id === mainUser) {
          connectedIds.add(node.id);
        }
      }
      let nodes = baseNodes.filter((node) => connectedIds.has(node.id));
      let links = filteredLinks;
      if (state.search !== '') {
        const matchedIds = new Set();
        for (const node of nodes) {
          const labelValue = String(node.label || '').toLowerCase();
          const idValue = String(node.id || '').toLowerCase();
          if (labelValue.includes(state.search) || idValue.includes(state.search)) {
            matchedIds.add(node.id);
            for (const neighborId of adjacency.get(node.id) || []) {
              matchedIds.add(neighborId);
            }
          }
        }
        nodes = nodes.filter((node) => matchedIds.has(node.id));
        const allowed = new Set(nodes.map((node) => node.id));
        links = links.filter((link) => allowed.has(link.source) && allowed.has(link.target));
      }
      if (state.focusMode && state.focusedId) {
        const focusedNeighborhood = collectNeighborhood(state.focusedId, links, 2);
        nodes = nodes.filter((node) => focusedNeighborhood.has(node.id));
        const allowed = new Set(nodes.map((node) => node.id));
        links = links.filter((link) => allowed.has(link.source) && allowed.has(link.target));
      }
      const clustered = applyClusterMode(nodes, links);
      return clustered;
    }

    function applyClusterMode(nodes, links) {
      if (!state.clusterMode) {
        return {
          nodes: nodes.map((node) => ({...node})),
          links: links.map((link) => ({...link}))
        };
      }
      const nodeIds = new Set(nodes.map((node) => node.id));
      const components = findComponents(nodeIds, links);
      const componentByNode = new Map();
      const collapsedComponents = new Set();
      for (const component of components) {
        for (const nodeId of component.members) {
          componentByNode.set(nodeId, component.id);
        }
        const hasMain = component.members.includes(mainUser);
        const hasFocus = state.focusedId && component.members.includes(state.focusedId);
        if (component.members.length >= 3 && !hasMain && !hasFocus) {
          collapsedComponents.add(component.id);
        }
      }
      const renderNodes = [];
      const collapseNodeByComponent = new Map();
      for (const node of nodes) {
        const componentId = componentByNode.get(node.id);
        if (collapsedComponents.has(componentId)) {
          continue;
        }
        renderNodes.push({...node});
      }
      for (const component of components) {
        if (!collapsedComponents.has(component.id)) {
          continue;
        }
        const scores = component.members.map((member) => {
          const value = sourceNodes.find((node) => node.id === member);
          if (value) {
            return value.suspicious_score;
          }
          return 0;
        });
        const maxScore = Math.max(...scores, 0);
        const clusterId = `cluster:${component.id}`;
        collapseNodeByComponent.set(component.id, clusterId);
        renderNodes.push({
          id: clusterId,
          label: `Cluster ${component.members.length}`,
          label_short: `Cluster ${component.members.length}`,
          color: '#64748b',
          size: Math.min(28, 10 + (Math.sqrt(component.members.length) * 3)),
          followers: 0,
          following: 0,
          suspicious_score: maxScore,
          synthetic: true
        });
      }
      const aggregateMap = new Map();
      for (const link of links) {
        const sourceComponent = componentByNode.get(link.source);
        const targetComponent = componentByNode.get(link.target);
        const sourceId = collapsedComponents.has(sourceComponent)
          ? collapseNodeByComponent.get(sourceComponent)
          : link.source;
        const targetId = collapsedComponents.has(targetComponent)
          ? collapseNodeByComponent.get(targetComponent)
          : link.target;
        if (!sourceId || !targetId || sourceId === targetId) {
          continue;
        }
        const key = [sourceId, targetId, link.type].join('||');
        if (!aggregateMap.has(key)) {
          aggregateMap.set(key, {
            source: sourceId,
            target: targetId,
            type: link.type,
            color: link.color,
            width: 0,
            interaction_count: 0,
            last_interaction: '',
            parsed_time: link.parsed_time,
            fallback_time: link.fallback_time
          });
        }
        const merged = aggregateMap.get(key);
        merged.width += link.width;
        merged.interaction_count += link.interaction_count;
        if (link.last_interaction > merged.last_interaction) {
          merged.last_interaction = link.last_interaction;
        }
      }
      const renderLinks = [...aggregateMap.values()].map((link) => ({
        ...link,
        width: Math.min(8, Math.max(1, link.width))
      }));
      return {nodes: renderNodes, links: renderLinks};
    }

    async function renderD3(renderData) {
      stopTimeline();
      if (state.timelineRunning) {
        runTimeline();
      }
      if (pendingViewportTimer !== null) {
        window.clearTimeout(pendingViewportTimer);
        pendingViewportTimer = null;
      }
      graphRoot.innerHTML = '';
      const width = graphRoot.clientWidth;
      const height = graphRoot.clientHeight;
      await computeWorkerPrelayout(renderData.nodes, width, height);
      svg = d3.select('#graph').append('svg')
        .attr('width', width)
        .attr('height', height)
        .attr('role', 'img')
        .attr('aria-label', 'Interactive social graph');
      container = svg.append('g');
      zoomBehavior = d3.zoom().scaleExtent([0.1, 4]).on('zoom', (event) => {
        zoomTransform = event.transform;
        state.zoomLevel = zoomTransform.k;
        container.attr('transform', zoomTransform);
        updateLabelVisibility();
      });
      svg.call(zoomBehavior);
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
      const links = container.append('g')
        .selectAll('line')
        .data(renderData.links)
        .join('line')
        .attr('stroke', (link) => link.color)
        .attr('stroke-width', (link) => link.width)
        .attr('stroke-opacity', 0.68)
        .attr('marker-end', 'url(#arrow)')
        .on('mouseover', (event, link) => showEdgeTooltip(event, link))
        .on('mouseout', hideTooltip);
      const nodes = container.append('g')
        .selectAll('g')
        .data(renderData.nodes)
        .join('g')
        .attr('tabindex', 0)
        .on('click', (_, node) => onNodeClick(node))
        .call(d3.drag()
          .on('start', (event) => dragStarted(event))
          .on('drag', (event) => dragged(event))
          .on('end', (event) => dragEnded(event)));
      nodes.append('circle')
        .attr('r', (node) => node.size)
        .attr('fill', (node) => riskColor(node))
        .attr('stroke', (node) => {
          if (node.id === state.focusedId) {
            return '#f8fafc';
          }
          if (node.id === state.selectedId) {
            return '#7dd3fc';
          }
          return 'rgba(232, 237, 247, 0.34)';
        })
        .attr('stroke-width', (node) => {
          if (node.id === state.focusedId) {
            return 2;
          }
          if (node.id === state.selectedId) {
            return 1.6;
          }
          return 1;
        })
        .on('mouseover', (event, node) => showNodeTooltip(event, node))
        .on('mouseout', hideTooltip);
      nodes.filter((node) => topRiskNodes(renderData.nodes).has(node.id))
        .append('text')
        .text('!')
        .attr('text-anchor', 'middle')
        .attr('dy', 4)
        .style('font-size', '10px')
        .style('font-weight', '700')
        .style('fill', '#05080d')
        .style('pointer-events', 'none');
      nodes.append('text')
        .text((node) => node.label_short || String(node.label || '').split('\n')[0])
        .attr('class', 'node-label')
        .attr('text-anchor', 'middle')
        .attr('y', (node) => node.size + 10)
        .style('font-size', '10px')
        .style('fill', '#cbd5e1')
        .style('font-weight', '500')
        .style('pointer-events', 'none');
      simulation = d3.forceSimulation(renderData.nodes)
        .force('link', d3.forceLink(renderData.links).id((node) => node.id).distance(100))
        .force('charge', d3.forceManyBody().strength(-900).distanceMax(500))
        .force('center', d3.forceCenter(width / 2, height / 2))
        .force('collide', d3.forceCollide().radius((node) => node.size * 2.2))
        .on('tick', () => {
          links
            .attr('x1', (link) => link.source.x)
            .attr('y1', (link) => link.source.y)
            .attr('x2', (link) => link.target.x)
            .attr('y2', (link) => link.target.y);
          nodes.attr('transform', (node) => `translate(${node.x},${node.y})`);
        });
      if (state.reducedMotion) {
        simulation.alpha(0.22);
      }
      updateLabelVisibility();
      pendingViewportTimer = window.setTimeout(() => {
        applyDefaultViewport();
      }, 320);
      function dragStarted(event) {
        if (!event.active) {
          simulation.alphaTarget(0.3).restart();
        }
        event.subject.fx = event.subject.x;
        event.subject.fy = event.subject.y;
      }
      function dragged(event) {
        event.subject.fx = event.x;
        event.subject.fy = event.y;
      }
      function dragEnded(event) {
        if (!event.active) {
          simulation.alphaTarget(0);
        }
        event.subject.fx = null;
        event.subject.fy = null;
      }
    }

    function applyDefaultViewport() {
      if (!state.focusMode || !state.focusedId) {
        fitToView();
        return;
      }
      centerOnNode(state.focusedId);
    }

    function onNodeClick(node) {
      if (String(node.id).startsWith('cluster:')) {
        state.clusterMode = false;
        clusterModeInput.checked = false;
        renderGraph();
        return;
      }
      state.selectedId = node.id;
      if (!state.focusMode) {
        updateInspector();
        return;
      }
      if (state.focusedId === node.id) {
        state.focusedId = null;
        renderGraph();
        return;
      }
      state.focusedId = node.id;
      renderGraph();
    }

    function updateInspector() {
      if (renderedNodes.length === 0 || !state.selectedId) {
        inspectorName.textContent = 'No node available';
        inspectorScore.textContent = '0.00';
        inspectorFollowers.textContent = '0';
        inspectorFollowing.textContent = '0';
        inspectorConnections.textContent = '0';
        inspectorStatus.textContent = 'Try reducing filters to see more nodes.';
        return;
      }
      const selectedNode = renderedNodes.find((node) => node.id === state.selectedId);
      if (!selectedNode) {
        inspectorName.textContent = 'No node selected';
        inspectorScore.textContent = '0.00';
        inspectorFollowers.textContent = '0';
        inspectorFollowing.textContent = '0';
        inspectorConnections.textContent = '0';
        inspectorStatus.textContent = 'Click a node to inspect it.';
        return;
      }
      const connectionSet = new Set();
      for (const link of renderedLinks) {
        const sourceId = String(link.source.id || link.source);
        const targetId = String(link.target.id || link.target);
        if (sourceId === selectedNode.id) {
          connectionSet.add(targetId);
        }
        if (targetId === selectedNode.id) {
          connectionSet.add(sourceId);
        }
      }
      const roundedScore = Number(selectedNode.suspicious_score || 0).toFixed(2);
      inspectorName.textContent = `@${selectedNode.label_short || selectedNode.id}`;
      inspectorScore.textContent = roundedScore;
      inspectorFollowers.textContent = String(selectedNode.followers || 0);
      inspectorFollowing.textContent = String(selectedNode.following || 0);
      inspectorConnections.textContent = String(connectionSet.size);
      if (state.focusMode && state.focusedId) {
        inspectorStatus.textContent = `Focus mode is active on @${state.focusedId}.`;
        return;
      }
      inspectorStatus.textContent = 'Click another node to compare profile signals.';
    }

    function showNodeTooltip(event, node) {
      const score = Number(node.suspicious_score || 0).toFixed(2);
      tooltip.style('opacity', 1)
        .style('transform', 'translateY(0)')
        .html(`<strong>${node.label_short}</strong><br>Score: ${score}<br>Followers: ${node.followers}<br>Following: ${node.following}`)
        .style('left', `${event.pageX + 10}px`)
        .style('top', `${event.pageY - 12}px`);
    }

    function showEdgeTooltip(event, link) {
      const details = link.last_interaction === ''
        ? 'n/a'
        : String(link.last_interaction);
      tooltip.style('opacity', 1)
        .style('transform', 'translateY(0)')
        .html(`<strong>${link.type}</strong><br>Interactions: ${link.interaction_count}<br>Last: ${details}`)
        .style('left', `${event.pageX + 10}px`)
        .style('top', `${event.pageY - 12}px`);
    }

    function hideTooltip() {
      tooltip.style('opacity', 0)
        .style('transform', 'translateY(4px)');
    }

    function updateFocusBanner() {
      if (!state.focusMode || !state.focusedId) {
        focusBanner.textContent = '';
        return;
      }
      focusBanner.textContent = `Focus: @${state.focusedId} (two-hop neighborhood)`;
    }

    function collectNeighborhood(centerId, links, hops) {
      const graph = new Map();
      for (const link of links) {
        if (!graph.has(link.source)) {
          graph.set(link.source, new Set());
        }
        if (!graph.has(link.target)) {
          graph.set(link.target, new Set());
        }
        graph.get(link.source).add(link.target);
        graph.get(link.target).add(link.source);
      }
      const seen = new Set([centerId]);
      let frontier = new Set([centerId]);
      for (let depth = 0; depth < hops; depth += 1) {
        const next = new Set();
        for (const nodeId of frontier) {
          const neighbors = graph.get(nodeId) || new Set();
          for (const neighborId of neighbors) {
            if (!seen.has(neighborId)) {
              seen.add(neighborId);
              next.add(neighborId);
            }
          }
        }
        frontier = next;
      }
      return seen;
    }

    function findComponents(nodeIds, links) {
      const neighbors = new Map();
      for (const nodeId of nodeIds) {
        neighbors.set(nodeId, new Set());
      }
      for (const link of links) {
        if (!neighbors.has(link.source) || !neighbors.has(link.target)) {
          continue;
        }
        neighbors.get(link.source).add(link.target);
        neighbors.get(link.target).add(link.source);
      }
      const visited = new Set();
      const components = [];
      let index = 0;
      for (const nodeId of nodeIds) {
        if (visited.has(nodeId)) {
          continue;
        }
        const members = [];
        const queue = [nodeId];
        visited.add(nodeId);
        while (queue.length > 0) {
          const current = queue.pop();
          members.push(current);
          for (const neighbor of neighbors.get(current) || []) {
            if (visited.has(neighbor)) {
              continue;
            }
            visited.add(neighbor);
            queue.push(neighbor);
          }
        }
        components.push({id: index, members});
        index += 1;
      }
      return components;
    }

    function normalizeLinkTime(link) {
      const times = sourceLinks
        .map((item) => item.parsed_time || item.fallback_time)
        .sort((left, right) => left - right);
      if (times.length === 0) {
        return 1;
      }
      const minTime = times[0];
      const maxTime = times[times.length - 1];
      const value = link.parsed_time || link.fallback_time;
      if (maxTime === minTime) {
        return 1;
      }
      return (value - minTime) / (maxTime - minTime);
    }

    function parseTimeValue(value) {
      if (value === null || value === undefined || value === '') {
        return null;
      }
      const asNumber = Number(value);
      if (!Number.isNaN(asNumber) && Number.isFinite(asNumber)) {
        return asNumber;
      }
      const asDate = Date.parse(String(value));
      if (!Number.isNaN(asDate)) {
        return asDate;
      }
      return null;
    }

    function buildAdjacency(nodes, links) {
      const result = new Map();
      for (const node of nodes) {
        result.set(node.id, new Set());
      }
      for (const link of links) {
        if (!result.has(link.source) || !result.has(link.target)) {
          continue;
        }
        result.get(link.source).add(link.target);
        result.get(link.target).add(link.source);
      }
      return result;
    }

    function topRiskNodes(nodes) {
      const sorted = [...nodes]
        .sort((left, right) => right.suspicious_score - left.suspicious_score)
        .slice(0, 5);
      return new Set(sorted.map((node) => node.id));
    }

    function riskColor(node) {
      if (node.synthetic) {
        return '#64748b';
      }
      const score = Number(node.suspicious_score || 0);
      const high = Math.min(1, Math.max(0, score));
      const r = Math.round((40 * (1 - high)) + (239 * high));
      const g = Math.round((130 * (1 - high)) + (68 * high));
      const b = Math.round((180 * (1 - high)) + (68 * high));
      return `rgb(${r}, ${g}, ${b})`;
    }

    function updateLabelVisibility() {
      if (!svg) {
        return;
      }
      const threshold = 0.9;
      svg.selectAll('.node-label')
        .style('display', (node) => {
          if (state.zoomLevel >= threshold) {
            return 'block';
          }
          if (node.size >= 9) {
            return 'block';
          }
          if (node.id === state.focusedId) {
            return 'block';
          }
          return 'none';
        });
    }

    function fitToView() {
      if (!svg || renderedNodes.length === 0) {
        return;
      }
      const width = graphRoot.clientWidth;
      const height = graphRoot.clientHeight;
      const xs = renderedNodes.map((node) => node.x || 0);
      const ys = renderedNodes.map((node) => node.y || 0);
      const minX = Math.min(...xs);
      const maxX = Math.max(...xs);
      const minY = Math.min(...ys);
      const maxY = Math.max(...ys);
      const graphWidth = Math.max(1, maxX - minX);
      const graphHeight = Math.max(1, maxY - minY);
      const scale = Math.min(
        2.8,
        Math.max(0.25, 0.9 / Math.max(graphWidth / width, graphHeight / height))
      );
      const translateX = (width / 2) - ((minX + maxX) / 2 * scale);
      const translateY = (height / 2) - ((minY + maxY) / 2 * scale);
      const transform = d3.zoomIdentity.translate(translateX, translateY).scale(scale);
      svg.transition().duration(state.reducedMotion ? 0 : 280).call(zoomBehavior.transform, transform);
    }

    function centerOnNode(nodeId) {
      if (!svg || !zoomBehavior) {
        return;
      }
      const selectedNode = renderedNodes.find((node) => node.id === nodeId);
      if (!selectedNode) {
        fitToView();
        return;
      }
      const width = graphRoot.clientWidth;
      const height = graphRoot.clientHeight;
      const nodeX = selectedNode.x ?? (width / 2);
      const nodeY = selectedNode.y ?? (height / 2);
      const scale = 1.25;
      const transform = d3.zoomIdentity
        .translate((width / 2) - (nodeX * scale), (height / 2) - (nodeY * scale))
        .scale(scale);
      svg.transition().duration(state.reducedMotion ? 0 : 280).call(zoomBehavior.transform, transform);
    }

    function handleKeyboardShortcuts(event) {
      if (event.key === '/') {
        event.preventDefault();
        searchInput.focus();
        return;
      }
      if (event.key === 'f' || event.key === 'F') {
        event.preventDefault();
        fitToView();
        return;
      }
      if (event.key === 'Escape') {
        state.focusedId = null;
        renderGraph();
        return;
      }
      if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') {
        return;
      }
      if (renderedNodes.length === 0) {
        return;
      }
      const userNodes = renderedNodes.filter((node) => !String(node.id).startsWith('cluster:'));
      if (userNodes.length === 0) {
        return;
      }
      const ordered = [...userNodes].sort((left, right) =>
        String(left.label_short).localeCompare(String(right.label_short))
      );
      let index = ordered.findIndex((node) => node.id === state.focusedId);
      if (index < 0) {
        index = 0;
      }
      if (event.key === 'ArrowRight') {
        index = (index + 1) % ordered.length;
      }
      if (event.key === 'ArrowLeft') {
        index = (index - 1 + ordered.length) % ordered.length;
      }
      state.focusedId = ordered[index].id;
      state.selectedId = ordered[index].id;
      renderGraph();
    }

    function exportJson() {
      const exportData = {
        nodes: renderedNodes,
        links: renderedLinks
      };
      downloadText(
        `graph_${mainUser}.json`,
        JSON.stringify(exportData, null, 2),
        'application/json;charset=utf-8'
      );
    }

    function exportCsv() {
      const rows = ['source,target,type,weight,interaction_count,last_interaction'];
      for (const link of renderedLinks) {
        const source = String(link.source.id || link.source);
        const target = String(link.target.id || link.target);
        const line = [
          source,
          target,
          link.type,
          link.width,
          link.interaction_count,
          `"${String(link.last_interaction || '').replaceAll('"', '""')}"`
        ].join(',');
        rows.push(line);
      }
      downloadText(
        `graph_${mainUser}.csv`,
        rows.join('\n'),
        'text/csv;charset=utf-8'
      );
    }

    function exportSvg() {
      if (!svg) {
        return;
      }
      const element = svg.node();
      const serializer = new XMLSerializer();
      const source = serializer.serializeToString(element);
      downloadText(`graph_${mainUser}.svg`, source, 'image/svg+xml;charset=utf-8');
    }

    function exportPng() {
      if (!svg) {
        return;
      }
      const element = svg.node();
      const serializer = new XMLSerializer();
      const source = serializer.serializeToString(element);
      const image = new Image();
      const blob = new Blob([source], {type: 'image/svg+xml;charset=utf-8'});
      const url = URL.createObjectURL(blob);
      image.onload = () => {
        const canvas = document.createElement('canvas');
        canvas.width = element.clientWidth || graphContainer.clientWidth;
        canvas.height = element.clientHeight || graphContainer.clientHeight;
        const context = canvas.getContext('2d');
        context.fillStyle = '#0a0c10';
        context.fillRect(0, 0, canvas.width, canvas.height);
        context.drawImage(image, 0, 0);
        URL.revokeObjectURL(url);
        canvas.toBlob((pngBlob) => {
          if (!pngBlob) {
            return;
          }
          downloadBlob(`graph_${mainUser}.png`, pngBlob);
        });
      };
      image.src = url;
    }

    function downloadText(filename, text, mimeType) {
      const blob = new Blob([text], {type: mimeType});
      downloadBlob(filename, blob);
    }

    function downloadBlob(filename, blob) {
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = filename;
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
      URL.revokeObjectURL(url);
    }

    async function computeWorkerPrelayout(nodes, width, height) {
      if (!window.Worker || nodes.length < 60) {
        return;
      }
      const payload = {
        count: nodes.length,
        width,
        height
      };
      const workerSource = `
        self.onmessage = (event) => {
          const count = event.data.count;
          const width = event.data.width;
          const height = event.data.height;
          const radius = Math.min(width, height) * 0.32;
          const positions = [];
          for (let index = 0; index < count; index += 1) {
            const angle = (index / Math.max(1, count)) * Math.PI * 2;
            const spread = radius * (0.6 + (index / Math.max(1, count)) * 0.4);
            const x = (width / 2) + Math.cos(angle) * spread;
            const y = (height / 2) + Math.sin(angle) * spread;
            positions.push({x, y});
          }
          self.postMessage(positions);
        };
      `;
      const workerBlob = new Blob([workerSource], {type: 'application/javascript'});
      const worker = new Worker(URL.createObjectURL(workerBlob));
      const positions = await new Promise((resolve) => {
        worker.onmessage = (event) => resolve(event.data);
        worker.postMessage(payload);
      });
      worker.terminate();
      for (let index = 0; index < nodes.length; index += 1) {
        const position = positions[index];
        if (!position) {
          continue;
        }
        nodes[index].x = position.x;
        nodes[index].y = position.y;
      }
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
