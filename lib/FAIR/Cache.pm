package FAIR::Cache;

use strict;
use warnings;
use Exporter 'import';
use Carp     qw(croak);
use English  qw(-no_match_vars);
use JSON::PP qw(decode_json encode_json);

our $VERSION = '0.1.0';

our @EXPORT_OK = qw(
  load_cache
  save_cache
  new_graph
  save_graph
  load_graph
  graph_nodes
  graph_edges
  graph_has_node
  graph_add_node
  graph_get_node
  graph_has_edge
  graph_add_edge
  graph_get_edge
  graph_successors
  graph_predecessors
  graph_neighbors
  graph_degree
  graph_copy
  graph_subgraph
  graph_merge
  graph_shortest_path
  graph_shared_neighbors
);

sub load_cache {
    my ($path) = @_;
    if (!defined $path || !-e $path) {
        return {};
    }

    my $content = _read_file($path);
    if (!defined $content || $content eq q{}) {
        return {};
    }

    my $data;
    eval { $data = decode_json($content); 1 } or return {};
    if (ref($data) eq 'HASH') {
        return $data;
    }
    return {};
}

sub save_cache {
    my ($path, $data) = @_;
    $data ||= {};
    my $encoder = JSON::PP -> new;
    $encoder -> utf8;
    $encoder -> pretty;
    _write_file($path, $encoder -> encode($data));
    return;
}

sub new_graph {
    my (%args) = @_;
    my $directed = 1;
    if (exists $args{directed}) {
        $directed = $args{directed};
    }
    my $directed_value = 0;
    if ($directed) {
        $directed_value = 1;
    }
    return {
        directed => $directed_value,
        nodes    => {},
        edges    => {},
    };
}

sub save_graph {
    my ($path, $graph) = @_;
    $graph ||= new_graph();

    my $directed_flag = JSON::PP::false;
    if ($graph -> {directed}) {
        $directed_flag = JSON::PP::true;
    }
    my $payload = {
        directed => $directed_flag,
        nodes    => [],
        edges    => [],
    };

    for my $node_id (sort keys %{$graph -> {nodes} || {}}) {
        push @{$payload -> {nodes}},
          {
            id         => $node_id,
            attributes =>
              _coerce_json_attributes($graph -> {nodes}{$node_id}),
          };
    }

    for my $source (sort keys %{$graph -> {edges} || {}}) {
        for my $target (sort keys %{$graph -> {edges}{$source} || {}}) {
            push @{$payload -> {edges}},
              {
                source     => $source,
                target     => $target,
                attributes => _coerce_json_attributes(
                    $graph -> {edges}{$source}{$target}
                ),
              };
        }
    }

    my $encoder = JSON::PP -> new;
    $encoder -> utf8;
    $encoder -> pretty;
    _write_file($path, $encoder -> encode($payload));
    return;
}

sub load_graph {
    my ($path) = @_;
    if (!defined $path || !-e $path) {
        return new_graph(directed => 1);
    }

    my $content = _read_file($path);
    my $payload;
    eval { $payload = decode_json($content); 1 }
      or return new_graph(directed => 1);

    my $directed_value = 0;
    if ($payload -> {directed}) {
        $directed_value = 1;
    }
    my $graph = new_graph(directed => $directed_value);

    for my $node (@{$payload -> {nodes} || []}) {
        my $node_id = $node -> {id};
        if (!defined $node_id || $node_id eq q{}) {
            next;
        }
        my $attributes = {};
        if (ref($node -> {attributes}) eq 'HASH') {
            $attributes = $node -> {attributes};
        }
        $graph -> {nodes}{$node_id} = $attributes;
    }

    for my $edge (@{$payload -> {edges} || []}) {
        my $source = $edge -> {source};
        my $target = $edge -> {target};
        if (!defined $source || !defined $target) {
            next;
        }

        my $attrs = {};
        if (ref($edge -> {attributes}) eq 'HASH') {
            $attrs = $edge -> {attributes};
        }
        $graph -> {edges}{$source}{$target} = $attrs;
        if (!$graph -> {directed}) {
            $graph -> {edges}{$target}{$source} = {%{$attrs}};
        }

        $graph -> {nodes}{$source} ||= {};
        $graph -> {nodes}{$target} ||= {};
    }

    return $graph;
}

sub graph_nodes {
    my ($graph) = @_;
    return keys %{$graph -> {nodes} || {}};
}

sub graph_edges {
    my ($graph) = @_;
    my @edges;
    for my $source (keys %{$graph -> {edges} || {}}) {
        for my $target (keys %{$graph -> {edges}{$source} || {}}) {
            push @edges,
              [$source, $target, $graph -> {edges}{$source}{$target}];
        }
    }
    return @edges;
}

sub graph_has_node {
    my ($graph, $node) = @_;
    return exists($graph -> {nodes}{$node});
}

sub graph_add_node {
    my ($graph, $node, $attrs) = @_;
    $attrs ||= {};
    $graph -> {nodes}{$node} ||= {};
    for my $key (keys %{$attrs}) {
        $graph -> {nodes}{$node}{$key} = $attrs -> {$key};
    }
    return;
}

sub graph_get_node {
    my ($graph, $node) = @_;
    return $graph -> {nodes}{$node};
}

sub graph_has_edge {
    my ($graph, $source, $target) = @_;
    return exists($graph -> {edges}{$source}{$target});
}

sub graph_add_edge {
    my ($graph, $source, $target, $attrs) = @_;
    $attrs ||= {};
    $graph -> {edges}{$source} ||= {};
    $graph -> {edges}{$source}{$target} ||= {};
    for my $key (keys %{$attrs}) {
        $graph -> {edges}{$source}{$target}{$key} = $attrs -> {$key};
    }

    $graph -> {nodes}{$source} ||= {};
    $graph -> {nodes}{$target} ||= {};

    if (!$graph -> {directed}) {
        $graph -> {edges}{$target} ||= {};
        $graph -> {edges}{$target}{$source} =
          {%{$graph -> {edges}{$source}{$target}}};
    }
    return;
}

sub graph_get_edge {
    my ($graph, $source, $target) = @_;
    return $graph -> {edges}{$source}{$target};
}

sub graph_successors {
    my ($graph, $node) = @_;
    return keys %{$graph -> {edges}{$node} || {}};
}

sub graph_predecessors {
    my ($graph, $node) = @_;
    my @pred;
    for my $source (keys %{$graph -> {edges} || {}}) {
        if (exists $graph -> {edges}{$source}{$node}) {
            push @pred, $source;
        }
    }
    return @pred;
}

sub graph_neighbors {
    my ($graph, $node) = @_;
    my %neighbors;
    for my $successor (graph_successors($graph, $node)) {
        $neighbors{$successor} = 1;
    }
    for my $predecessor (graph_predecessors($graph, $node)) {
        $neighbors{$predecessor} = 1;
    }
    return keys %neighbors;
}

sub graph_degree {
    my ($graph, $node) = @_;
    my $degree = scalar(graph_successors($graph, $node)) +
      scalar(graph_predecessors($graph, $node));
    return $degree;
}

sub graph_copy {
    my ($graph) = @_;
    my $json = encode_json($graph);
    return decode_json($json);
}

sub graph_subgraph {
    my ($graph, $allowed_nodes) = @_;
    my %allowed = map { $_ => 1 } @{$allowed_nodes || []};

    my $sub = new_graph(directed => $graph -> {directed});
    for my $node (keys %allowed) {
        if (!exists $graph -> {nodes}{$node}) {
            next;
        }
        $sub -> {nodes}{$node} = {%{$graph -> {nodes}{$node} || {}}};
    }

    for my $source (keys %{$graph -> {edges} || {}}) {
        if (!$allowed{$source}) {
            next;
        }
        for my $target (keys %{$graph -> {edges}{$source} || {}}) {
            if (!$allowed{$target}) {
                next;
            }
            graph_add_edge($sub, $source, $target,
                {%{$graph -> {edges}{$source}{$target} || {}}});
        }
    }

    return $sub;
}

sub graph_merge {
    my ($left_graph, $right_graph) = @_;
    my $merged_graph = new_graph(directed => 1);

    if ($left_graph && !$left_graph -> {directed}) {
        $merged_graph -> {directed} = 0;
    }
    if ($right_graph && !$right_graph -> {directed}) {
        $merged_graph -> {directed} = 0;
    }

    _merge_graph_into_target($merged_graph, $left_graph);
    _merge_graph_into_target($merged_graph, $right_graph);
    return $merged_graph;
}

sub graph_shortest_path {
    my ($graph, $start_node, $end_node) = @_;
    if (!$graph || !defined $start_node || !defined $end_node) {
        return [];
    }
    if (!graph_has_node($graph, $start_node)) {
        return [];
    }
    if (!graph_has_node($graph, $end_node)) {
        return [];
    }
    if ($start_node eq $end_node) {
        return [$start_node];
    }

    my %visited = ($start_node => 1);
    my @queue   = ([$start_node]);
    my $index   = 0;

    while ($index < scalar @queue) {
        my $path = $queue[$index];
        $index = $index + 1;

        my $current_node = $path -> [-1];
        for my $neighbor (sort graph_neighbors($graph, $current_node)) {
            if ($visited{$neighbor}) {
                next;
            }

            my @next_path = @{$path};
            push @next_path, $neighbor;
            if ($neighbor eq $end_node) {
                return \@next_path;
            }

            $visited{$neighbor} = 1;
            push @queue, \@next_path;
        }
    }

    return [];
}

sub graph_shared_neighbors {
    my ($graph, $left_node, $right_node) = @_;
    if (!$graph || !defined $left_node || !defined $right_node) {
        return [];
    }

    my %left_neighbors = map { $_ => 1 } graph_neighbors($graph, $left_node);
    my @shared_neighbors;

    for my $neighbor (sort graph_neighbors($graph, $right_node)) {
        if (!$left_neighbors{$neighbor}) {
            next;
        }
        push @shared_neighbors, $neighbor;
    }

    return \@shared_neighbors;
}

sub _merge_graph_into_target {
    my ($target_graph, $source_graph) = @_;
    if (!$source_graph) {
        return;
    }

    for my $node_id (graph_nodes($source_graph)) {
        my $source_attributes = graph_get_node($source_graph, $node_id) || {};
        if (!graph_has_node($target_graph, $node_id)) {
            graph_add_node($target_graph, $node_id, {%{$source_attributes}});
            next;
        }

        my $target_attributes = graph_get_node($target_graph, $node_id) || {};
        _merge_node_attributes($target_attributes, $source_attributes);
        graph_add_node($target_graph, $node_id, $target_attributes);
    }

    for my $edge (graph_edges($source_graph)) {
        my ($source_id, $target_id, $source_attributes) = @{$edge};
        if (!graph_has_edge($target_graph, $source_id, $target_id)) {
            graph_add_edge(
                $target_graph,
                $source_id,
                $target_id,
                {%{$source_attributes || {}}}
            );
            next;
        }

        my $target_attributes =
          graph_get_edge($target_graph, $source_id, $target_id) || {};
        _merge_edge_attributes($target_attributes, $source_attributes || {});
        graph_add_edge(
            $target_graph,
            $source_id,
            $target_id,
            $target_attributes
        );
    }

    return;
}

sub _merge_node_attributes {
    my ($target_attributes, $source_attributes) = @_;

    for my $key (keys %{$source_attributes}) {
        my $source_value = $source_attributes -> {$key};
        if (!exists $target_attributes -> {$key}) {
            $target_attributes -> {$key} = $source_value;
            next;
        }

        if ($key eq 'count') {
            my $target_count = $target_attributes -> {$key} // 0;
            my $source_count = $source_value // 0;
            $target_attributes -> {$key} = $target_count + $source_count;
            next;
        }

        if (!defined $target_attributes -> {$key}
            || $target_attributes -> {$key} eq q{})
        {
            $target_attributes -> {$key} = $source_value;
        }
    }

    return;
}

sub _merge_edge_attributes {
    my ($target_attributes, $source_attributes) = @_;

    my $target_weight = $target_attributes -> {weight} // 0;
    my $source_weight = $source_attributes -> {weight} // 0;
    $target_attributes -> {weight} = $target_weight + $source_weight;

    my @target_interactions = @{$target_attributes -> {interactions} || []};
    my @source_interactions = @{$source_attributes -> {interactions} || []};
    $target_attributes -> {interactions} =
      [@target_interactions, @source_interactions];
    return;
}

sub _coerce_json_attributes {
    my ($attributes) = @_;
    $attributes ||= {};

    my $ok = eval { encode_json($attributes); 1 };
    if ($ok) {
        return $attributes;
    }

    my %coerced;
    for my $key (keys %{$attributes}) {
        my $value         = $attributes -> {$key};
        my $coerced_value = q{};
        if (defined $value) {
            $coerced_value = "$value";
        }
        $coerced{$key} = $coerced_value;
    }
    return \%coerced;
}

sub _read_file {
    my ($path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path or return;
    my @lines   = <$fh>;
    my $content = join q{}, @lines;
    close $fh or croak "Cannot close $path: $OS_ERROR";
    return $content;
}

sub _write_file {
    my ($path, $content) = @_;
    open my $fh, '>:encoding(UTF-8)', $path
      or croak "Cannot write $path: $OS_ERROR";
    print {$fh} $content;
    close $fh or croak "Cannot close $path: $OS_ERROR";
    return;
}

1;
