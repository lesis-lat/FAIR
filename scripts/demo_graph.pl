#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";

use FAIR::Cache qw(new_graph save_graph save_cache graph_add_node graph_add_edge);
use FAIR::Visualization qw(generate_html_from_files);

our $VERSION = '0.1.0';

my $CACHE_PATH = 'cache.json';
my $GRAPH_PATH = 'graph.json';

my $graph = new_graph(directed => 1);

graph_add_node($graph, 'alice', { full_name => 'Alice A.', count => 2, followers => 120, following => 80 });
graph_add_node($graph, 'bob',   { full_name => 'Bob B.',   count => 1, followers => 50,  following => 10 });
graph_add_node($graph, 'carol', { full_name => 'Carol C.', count => 1, followers => 200, following => 30 });

graph_add_edge($graph, 'alice', 'bob',   { interactions => [{ type => 'comment', post_id => 'p1' }], weight => 1 });
graph_add_edge($graph, 'bob',   'alice', { interactions => [{ type => 'mention', post_id => 'p2' }], weight => 1 });
graph_add_edge($graph, 'alice', 'carol', { interactions => [{ type => 'tag',     post_id => 'p3' }], weight => 1 });

my $cache = {
    alice => { username => 'alice', full_name => 'Alice A.', followers => 120, following => 80 },
    bob   => { username => 'bob',   full_name => 'Bob B.',   followers => 50,  following => 10 },
    carol => { username => 'carol', full_name => 'Carol C.', followers => 200, following => 30 },
};

save_cache($CACHE_PATH, $cache);
save_graph($GRAPH_PATH, $graph);

my $html_file = generate_html_from_files($GRAPH_PATH, $CACHE_PATH, 'alice', suspicious_calc => 0);
print "Generated $html_file\n";
