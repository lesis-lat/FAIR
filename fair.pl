#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use English qw(-no_match_vars);

use Getopt::Long qw(GetOptions);
use JSON::PP;

use FAIR::API qw(load_api_keys);
use FAIR::Cache qw(load_cache save_cache save_graph new_graph);
use FAIR::Graph qw(explore_users compute_suspicious_scores);
use FAIR::Visualization qw(generate_html_from_files);

our $VERSION = '0.1.0';

sub main {
    my %opts = (
        depth => 2,
        posts => 3,
    );

    GetOptions(
        'username=s'        => \$opts{username},
        'depth=i'           => \$opts{depth},
        'posts=i'           => \$opts{posts},
        'no-cache'          => \$opts{no_cache},
        'suspicious-calc'   => \$opts{suspicious_calc},
    ) or die "Invalid arguments\n";

    if (!defined $opts{username} || $opts{username} eq q{}) {
        die "Usage: perl fair.pl --username <handle> [--depth 2] [--posts 3] [--no-cache] [--suspicious-calc]\n";
    }

    my $username   = $opts{username};
    my $max_depth  = $opts{depth};
    my $posts_limit = $opts{posts};
    my $cache_path = 'cache.json';
    my $graph_path = 'graph.json';

    my $cache = load_cache($cache_path);
    if ($opts{no_cache}) {
        $cache = {};
    }

    my $api_keys = load_api_keys('keys.env');

    print "[INFO] API keys and cache loaded successfully.\n";
    print "Analyzing user: $username (depth=$max_depth, posts=$posts_limit)\n";

    my $graph = new_graph(directed => 1);
    my %explored_users;

    print "[INFO] Starting recursive exploration and graph generation...\n";

    explore_users(
        username    => $username,
        api_keys    => $api_keys,
        cache       => $cache,
        cache_path  => $cache_path,
        graph       => $graph,
        explored    => \%explored_users,
        max_depth   => $max_depth,
        posts_limit => $posts_limit,
        graph_path  => $graph_path,
    );

    if ($opts{suspicious_calc}) {
        compute_suspicious_scores($cache, $graph, $username);
    }

    save_cache($cache_path, $cache);
    save_graph($graph_path, $graph);

    my $html_generation_ok = eval {
        my $suspicious_calc_flag = 0;
        if ($opts{suspicious_calc}) {
            $suspicious_calc_flag = 1;
        }
        generate_html_from_files(
            $graph_path,
            $cache_path,
            $username,
            suspicious_calc => $suspicious_calc_flag,
        );
        1;
    };
    if (!$html_generation_ok) {
        print "[WARN] Failed to generate HTML graph: $EVAL_ERROR";
    }

    if (exists $cache -> {$username}) {
        my $json_encoder = JSON::PP -> new;
        $json_encoder -> utf8;
        $json_encoder -> pretty;
        my $json = $json_encoder -> encode($cache -> {$username});
        print $json;
    }
    return;
}

main();
