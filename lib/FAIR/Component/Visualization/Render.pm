package FAIR::Component::Visualization::Render;

use strict;
use warnings;
use Getopt::Long qw(GetOptionsFromArray);

use FAIR::Cache qw(load_cache load_graph);
use FAIR::Graph qw(build_connection_report);
use FAIR::Visualization qw(generate_html);

our $VERSION = '0.0.1';

sub new {
    my ($self, $message) = @_;
    my (
        $cache_path,
        $compare_with,
        $graph_path,
        $left_graph_path,
        $output_file,
        $right_graph_path,
        $suspicious_calc,
        $username,
    );

    GetOptionsFromArray(
        $message,
        'cache-path=s'        => \$cache_path,
        'compare-with=s'      => \$compare_with,
        'graph-path=s'        => \$graph_path,
        'left-graph-path=s'   => \$left_graph_path,
        'output-file=s'       => \$output_file,
        'right-graph-path=s'  => \$right_graph_path,
        'suspicious-calc'     => \$suspicious_calc,
        'username=s'          => \$username,
    );

    if (!defined $cache_path || $cache_path eq q{}) {
        return 0;
    }
    if (!defined $graph_path || $graph_path eq q{}) {
        return 0;
    }
    if (!defined $output_file || $output_file eq q{}) {
        return 0;
    }
    if (!defined $username || $username eq q{}) {
        return 0;
    }

    my $graph = load_graph($graph_path);
    my $cache = load_cache($cache_path);
    my $social_graph = {
        graph => $graph,
        cache => $cache,
    };
    my $comparison;
    my $suspicious_calc_flag = 0;

    if ($suspicious_calc) {
        $suspicious_calc_flag = 1;
    }

    if (defined $compare_with && $compare_with ne q{}) {
        my $left_graph = load_graph($left_graph_path);
        my $right_graph = load_graph($right_graph_path);
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

        $comparison = {
            primary_user   => $username,
            secondary_user => $compare_with,
            left_nodes     => \%left_nodes,
            right_nodes    => \%right_nodes,
            connection =>
              build_connection_report($graph, $username, $compare_with),
        };
    }

    return generate_html(
        $social_graph,
        $username,
        compare_with    => $compare_with,
        comparison      => $comparison,
        output_file     => $output_file,
        suspicious_calc => $suspicious_calc_flag,
    );
}

1;
