package FAIR::Network::Profile;

use strict;
use warnings;
use Getopt::Long qw(GetOptionsFromArray);
use Readonly;

use FAIR::Component::Graph::Score;
use FAIR::Component::Profile::Build;
use FAIR::Component::Profile::Report;
use FAIR::Component::Visualization::Render;

our $VERSION = '0.0.1';

Readonly my $DEFAULT_DEPTH             => 2;
Readonly my $DEFAULT_POSTS             => 3;
Readonly my $DEFAULT_PROFILE_TTL_HOURS => 24;
Readonly my $DEFAULT_POSTS_TTL_HOURS   => 12;

sub new {
    my ($self, $message) = @_;
    my (
        $depth,
        $no_cache,
        $posts,
        $posts_ttl_hours,
        $profile_ttl_hours,
        $suspicious_calc,
        $username,
    );
    my @result;

    $depth = $DEFAULT_DEPTH;
    $posts = $DEFAULT_POSTS;
    $profile_ttl_hours = $DEFAULT_PROFILE_TTL_HOURS;
    $posts_ttl_hours = $DEFAULT_POSTS_TTL_HOURS;

    GetOptionsFromArray(
        $message,
        'username=s'          => \$username,
        'depth=i'             => \$depth,
        'posts=i'             => \$posts,
        'no-cache'            => \$no_cache,
        'suspicious-calc'     => \$suspicious_calc,
        'profile-ttl-hours=i' => \$profile_ttl_hours,
        'posts-ttl-hours=i'   => \$posts_ttl_hours,
    );

    if (!defined $username || $username eq q{}) {
        return 0;
    }

    if ($profile_ttl_hours < 0) {
        return "--profile-ttl-hours must be >= 0\n";
    }

    if ($posts_ttl_hours < 0) {
        return "--posts-ttl-hours must be >= 0\n";
    }

    my $cache_path = 'cache.json';
    my $graph_path = 'graph.json';
    my $html_path = "graph_${username}.html";

    push @result, "[INFO] API keys and cache loaded successfully.\n";
    push @result,
      "Analyzing profile set: $username (depth=$depth, posts=$posts)\n";
    push @result,
      "[INFO] Starting recursive exploration and graph generation...\n";

    FAIR::Component::Profile::Build -> new(
        [
            '--cache-path'        => $cache_path,
            '--depth'             => $depth,
            '--graph-path'        => $graph_path,
            '--keys-path'         => 'keys.env',
            '--posts'             => $posts,
            '--posts-ttl-hours'   => $posts_ttl_hours,
            '--profile-ttl-hours' => $profile_ttl_hours,
            '--username'          => $username,
            ($no_cache ? '--no-cache' : ()),
        ]
    );

    if ($suspicious_calc) {
        FAIR::Component::Graph::Score -> new(
            [
                '--cache-path' => $cache_path,
                '--graph-path' => $graph_path,
                '--username'   => $username,
            ]
        );
    }
    my @render_message = (
        '--cache-path'  => $cache_path,
        '--graph-path'  => $graph_path,
        '--output-file' => $html_path,
        '--username'    => $username,
    );

    if ($suspicious_calc) {
        push @render_message, '--suspicious-calc';
    }

    my $html_file = FAIR::Component::Visualization::Render -> new(
        \@render_message
    );
    if (!$html_file) {
        push @result, "[WARN] Failed to generate HTML graph\n";
    }

    my $profile_json = FAIR::Component::Profile::Report -> new(
        [
            '--cache-path' => $cache_path,
            '--username'   => $username,
        ]
    );
    if ($profile_json) {
        push @result, $profile_json;
    }

    return @result;
}

1;
