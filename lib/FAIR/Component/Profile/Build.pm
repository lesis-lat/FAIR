package FAIR::Component::Profile::Build;

use strict;
use warnings;
use Getopt::Long qw(GetOptionsFromArray);
use Readonly;

use FAIR::API qw(load_api_keys);
use FAIR::Cache qw(load_cache save_cache save_graph new_graph);
use FAIR::Graph qw(explore_users);

our $VERSION = '0.0.1';

Readonly my $DEFAULT_DEPTH             => 2;
Readonly my $DEFAULT_POSTS             => 3;
Readonly my $DEFAULT_PROFILE_TTL_HOURS => 24;
Readonly my $DEFAULT_POSTS_TTL_HOURS   => 12;

sub new {
    my ($self, $message) = @_;
    my (
        $cache_path,
        $depth,
        $graph_path,
        $keys_path,
        $no_cache,
        $posts,
        $posts_ttl_hours,
        $profile_ttl_hours,
        $username,
    );

    $depth = $DEFAULT_DEPTH;
    $posts = $DEFAULT_POSTS;
    $profile_ttl_hours = $DEFAULT_PROFILE_TTL_HOURS;
    $posts_ttl_hours = $DEFAULT_POSTS_TTL_HOURS;

    GetOptionsFromArray(
        $message,
        'cache-path=s'        => \$cache_path,
        'depth=i'             => \$depth,
        'graph-path=s'        => \$graph_path,
        'keys-path=s'         => \$keys_path,
        'no-cache'            => \$no_cache,
        'posts=i'             => \$posts,
        'posts-ttl-hours=i'   => \$posts_ttl_hours,
        'profile-ttl-hours=i' => \$profile_ttl_hours,
        'username=s'          => \$username,
    );

    if (!defined $cache_path || $cache_path eq q{}) {
        return 0;
    }
    if (!defined $graph_path || $graph_path eq q{}) {
        return 0;
    }
    if (!defined $keys_path || $keys_path eq q{}) {
        return 0;
    }
    if (!defined $username || $username eq q{}) {
        return 0;
    }

    my $cache = load_cache($cache_path);
    if ($no_cache) {
        $cache = {};
    }

    my $api_keys = load_api_keys($keys_path);
    my $graph = new_graph(directed => 1);
    my %explored_users;

    explore_users(
        username          => $username,
        api_keys          => $api_keys,
        cache             => $cache,
        cache_path        => $cache_path,
        graph             => $graph,
        explored          => \%explored_users,
        max_depth         => $depth,
        posts_limit       => $posts,
        graph_path        => $graph_path,
        profile_ttl_hours => $profile_ttl_hours,
        posts_ttl_hours   => $posts_ttl_hours,
    );

    save_cache($cache_path, $cache);
    save_graph($graph_path, $graph);

    return {
        cache_path => $cache_path,
        graph_path => $graph_path,
        username   => $username,
    };
}

1;
