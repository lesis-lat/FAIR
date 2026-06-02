package FAIR::Component::Graph::Score;

use strict;
use warnings;
use Getopt::Long qw(GetOptionsFromArray);

use FAIR::Cache qw(load_cache load_graph save_cache save_graph);
use FAIR::Graph qw(compute_suspicious_scores);

our $VERSION = '0.0.1';

sub new {
    my ($self, $message) = @_;
    my ($cache_path, $compare_with, $graph_path, $username);

    GetOptionsFromArray(
        $message,
        'cache-path=s'   => \$cache_path,
        'compare-with=s' => \$compare_with,
        'graph-path=s'   => \$graph_path,
        'username=s'     => \$username,
    );

    if (!defined $cache_path || $cache_path eq q{}) {
        return 0;
    }
    if (!defined $graph_path || $graph_path eq q{}) {
        return 0;
    }
    if (!defined $username || $username eq q{}) {
        return 0;
    }

    my $cache = load_cache($cache_path);
    my $graph = load_graph($graph_path);

    compute_suspicious_scores($cache, $graph, $username);
    if (defined $compare_with && $compare_with ne q{}) {
        compute_suspicious_scores($cache, $graph, $compare_with);
    }

    save_cache($cache_path, $cache);
    save_graph($graph_path, $graph);
    return 1;
}

1;
