package FAIR::Component::Graph::Merge;

use strict;
use warnings;
use Getopt::Long qw(GetOptionsFromArray);

use FAIR::Cache qw(load_graph save_graph graph_merge);

our $VERSION = '0.0.1';

sub new {
    my ($self, $message) = @_;
    my ($graph_path, $left_graph_path, $right_graph_path);

    GetOptionsFromArray(
        $message,
        'graph-path=s'      => \$graph_path,
        'left-graph-path=s' => \$left_graph_path,
        'right-graph-path=s' => \$right_graph_path,
    );

    if (!defined $graph_path || $graph_path eq q{}) {
        return 0;
    }
    if (!defined $left_graph_path || $left_graph_path eq q{}) {
        return 0;
    }
    if (!defined $right_graph_path || $right_graph_path eq q{}) {
        return 0;
    }

    my $left_graph = load_graph($left_graph_path);
    my $right_graph = load_graph($right_graph_path);
    my $merged_graph = graph_merge($left_graph, $right_graph);
    my %left_nodes;
    my %right_nodes;

    if (ref($left_graph -> {nodes}) eq 'HASH') {
        for my $node_id (keys %{$left_graph -> {nodes}}) {
            $left_nodes{$node_id} = 1;
        }
    }

    if (ref($right_graph -> {nodes}) eq 'HASH') {
        for my $node_id (keys %{$right_graph -> {nodes}}) {
            $right_nodes{$node_id} = 1;
        }
    }

    save_graph($graph_path, $merged_graph);

    return {
        graph_path  => $graph_path,
        left_nodes  => \%left_nodes,
        right_nodes => \%right_nodes,
    };
}

1;
