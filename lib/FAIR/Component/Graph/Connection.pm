package FAIR::Component::Graph::Connection;

use strict;
use warnings;
use Getopt::Long qw(GetOptionsFromArray);

use FAIR::Cache qw(load_graph);
use FAIR::Graph qw(build_connection_report);

our $VERSION = '0.0.1';

sub new {
    my ($self, $message) = @_;
    my ($compare_with, $graph_path, $username);

    GetOptionsFromArray(
        $message,
        'compare-with=s' => \$compare_with,
        'graph-path=s'   => \$graph_path,
        'username=s'     => \$username,
    );

    if (!defined $compare_with || $compare_with eq q{}) {
        return 0;
    }
    if (!defined $graph_path || $graph_path eq q{}) {
        return 0;
    }
    if (!defined $username || $username eq q{}) {
        return 0;
    }

    my $graph = load_graph($graph_path);
    return build_connection_report($graph, $username, $compare_with);
}

1;
