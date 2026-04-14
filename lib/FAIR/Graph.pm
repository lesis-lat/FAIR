package FAIR::Graph;

use strict;
use warnings;
use Exporter 'import';
use English qw(-no_match_vars);
use Time::Piece;

use FAIR::API qw(fetch_profile fetch_posts extract_profile);
use FAIR::Cache qw(
  save_cache
  save_graph
  graph_has_node
  graph_add_node
  graph_get_node
  graph_has_edge
  graph_add_edge
  graph_get_edge
  graph_nodes
  graph_degree
);
use FAIR::Metrics qw(entropy temporal_entropy burstiness transform_burstiness);

our @EXPORT_OK = qw(
  update_graph_node
  explore_users
  compute_suspicious_scores
);

our $VERSION = '0.1.0';
my $DEFAULT_POSTS_LIMIT = 1 + 2;
my $DEFAULT_PROFILE_TTL_HOURS = (2 * 2 * 2) * (2 + 1);
my $DEFAULT_POSTS_TTL_HOURS = (2 * 2) * (2 + 1);
my $THIRTY = (2 * 2 * 2) + (2 * 2 * 2) + (2 * 2 * 2) + (2 * 2 * 2) - (2 + 1);
my $SIXTY = $THIRTY * 2;
my $SECONDS_PER_HOUR = $SIXTY * $SIXTY;
my $FIVE = 2 + 2 + 1;
my $THREE = 2 + 1;
my $SEVEN = 2 + 2 + 2 + 1;
my $TWENTY = $FIVE * (2 + 2);
my $ENGAGEMENT_THRESHOLD_DENOMINATOR = (2 * 2 * 2) * $FIVE * $FIVE;
my $SCORE_WEIGHT_BURST = $SEVEN / $TWENTY;
my $SCORE_WEIGHT_TEMPORAL = 1 / (2 * 2);
my $SCORE_WEIGHT_ENGAGEMENT = 1 / $FIVE;
my $SCORE_WEIGHT_USERNAME = $THREE / $TWENTY;
my $SCORE_WEIGHT_NAME = 1 / $TWENTY;
my $SCORE_NO_POSTS_ENGAGEMENT = 2 / $FIVE;
my $SCORE_NO_POSTS_USERNAME = $SEVEN / $TWENTY;
my $SCORE_NO_POSTS_NAME = 1 / (2 * 2);

sub update_graph_node {
    my ($graph, $username, %args) = @_;

    if (!graph_has_node($graph, $username)) {
        graph_add_node(
            $graph,
            $username,
            {
                count     => 1,
                full_name => $args{full_name} // $username,
                followers => $args{followers} // 0,
                following => $args{following} // 0,
            }
        );
        return;
    }

    my $node = graph_get_node($graph, $username);
    $node -> {count} = ($node -> {count} // 1) + 1;
    return;
}

sub explore_users {
    my (%args) = @_;

    my $username   = $args{username};
    my $api_keys   = $args{api_keys}   || [];
    my $cache      = $args{cache}      || {};
    my $cache_path = $args{cache_path};
    my $graph      = $args{graph};
    my $explored   = $args{explored}   || {};
    my $depth      = $args{depth}      // 1;
    my $max_depth  = $args{max_depth}  // 2;
    my $posts_limit = $args{posts_limit} // $DEFAULT_POSTS_LIMIT;
    my $profile_ttl_hours = $args{profile_ttl_hours} // $DEFAULT_PROFILE_TTL_HOURS;
    my $posts_ttl_hours = $args{posts_ttl_hours} // $DEFAULT_POSTS_TTL_HOURS;
    my $graph_path = $args{graph_path};

    if ($depth > $max_depth) {
        return;
    }
    if ($explored -> {$username}) {
        return;
    }
    $explored -> {$username} = 1;

    my $profile_data = $cache -> {$username};
    my $needs_fetch = _needs_profile_fetch(
        $profile_data,
        $profile_ttl_hours,
        $posts_ttl_hours,
    );
    my $fetch_error_message = q{};
    my $fetch_attempts = 0;
    my $empty_profile_responses = 0;
    if ($needs_fetch) {
        my $fetch_result = _fetch_profile_data(
            username     => $username,
            api_keys     => $api_keys,
            cache        => $cache,
            cache_path   => $cache_path,
            graph        => $graph,
            graph_path   => $graph_path,
            posts_limit  => $posts_limit,
            profile_ttl_hours => $profile_ttl_hours,
            posts_ttl_hours   => $posts_ttl_hours,
        );
        $profile_data = $fetch_result -> {profile_data};
        $fetch_error_message = $fetch_result -> {fetch_error_message};
        $fetch_attempts = $fetch_result -> {fetch_attempts};
        $empty_profile_responses = $fetch_result -> {empty_profile_responses};
    }
    if (!$needs_fetch && $profile_data) {
        _mark_cache_source($profile_data, 'cache');
    }

    if (!$profile_data) {
        _handle_missing_profile(
            graph                    => $graph,
            username                 => $username,
            fetch_error_message      => $fetch_error_message,
            fetch_attempts           => $fetch_attempts,
            empty_profile_responses  => $empty_profile_responses,
        );
        return;
    }
    if (($profile_data -> {account_type} // q{}) eq 'Private') {
        return;
    }

    update_graph_node(
        $graph,
        $username,
        full_name => $profile_data -> {full_name} // $username,
        followers => $profile_data -> {followers} // 0,
        following => $profile_data -> {following} // 0,
    );

    if (!exists $profile_data -> {latest_posts}) {
        return;
    }
    _explore_profile_posts(
        profile_data => $profile_data,
        username     => $username,
        graph        => $graph,
        api_keys     => $api_keys,
        cache        => $cache,
        cache_path   => $cache_path,
        explored     => $explored,
        depth        => $depth,
        max_depth    => $max_depth,
        posts_limit  => $posts_limit,
        graph_path   => $graph_path,
        profile_ttl_hours => $profile_ttl_hours,
        posts_ttl_hours   => $posts_ttl_hours,
    );
    return;
}

sub _fetch_profile_data {
    my (%args) = @_;
    my $username = $args{username};
    my $api_keys = $args{api_keys} || [];
    my $cache = $args{cache} || {};
    my $cache_path = $args{cache_path};
    my $graph = $args{graph};
    my $graph_path = $args{graph_path};
    my $posts_limit = $args{posts_limit};
    my $profile_ttl_hours = $args{profile_ttl_hours} // $DEFAULT_PROFILE_TTL_HOURS;
    my $posts_ttl_hours = $args{posts_ttl_hours} // $DEFAULT_POSTS_TTL_HOURS;

    my $profile_data;
    my $fetch_error_message = q{};
    my $fetch_attempts = 0;
    my $empty_profile_responses = 0;
    my $total_keys = scalar @{$api_keys};

    for my $key (@{$api_keys}) {
        $fetch_attempts = $fetch_attempts + 1;
        print "[INFO] Fetching profile $username with key $fetch_attempts/$total_keys\n";
        my $fetch_ok = eval {
            my $raw_data = fetch_profile($username, $key);
            if ($raw_data) {
                my $profile_info = extract_profile($raw_data);
                if ($profile_info) {
                    if (($profile_info -> {account_type} // q{}) ne 'Private') {
                        my $posts = fetch_posts($username, $key, $posts_limit);
                        $profile_info -> {latest_posts} = $posts;
                    }
                    _set_cache_metadata(
                        $profile_info,
                        $profile_ttl_hours,
                        $posts_ttl_hours,
                    );
                    $cache -> {$username} = $profile_info;
                    save_cache($cache_path, $cache);
                    $profile_data = $profile_info;
                    _save_graph_snapshot($graph_path, $graph);
                }
            }
            if (!$raw_data) {
                $empty_profile_responses = $empty_profile_responses + 1;
            }
            1;
        };
        if (!$fetch_ok) {
            $fetch_error_message = $EVAL_ERROR;
            next;
        }
        if ($profile_data) {
            last;
        }
    }

    return {
        profile_data             => $profile_data,
        fetch_error_message      => $fetch_error_message,
        fetch_attempts           => $fetch_attempts,
        empty_profile_responses  => $empty_profile_responses,
    };
}

sub _save_graph_snapshot {
    my ($graph_path, $graph) = @_;
    if (!$graph_path) {
        return;
    }
    my $save_graph_ok = eval {
        save_graph($graph_path, $graph);
        1;
    };
    if ($save_graph_ok) {
        return;
    }
    my $error_message = $EVAL_ERROR;
    if (defined $error_message && $error_message ne q{}) {
        print "[WARN] Failed to save graph snapshot: $error_message";
    }
    return;
}

sub _handle_missing_profile {
    my (%args) = @_;
    my $graph = $args{graph};
    my $username = $args{username};
    my $fetch_error_message = $args{fetch_error_message} // q{};
    my $fetch_attempts = $args{fetch_attempts} // 0;
    my $empty_profile_responses = $args{empty_profile_responses} // 0;

    update_graph_node(
        $graph,
        $username,
        full_name => $username,
        followers => 0,
        following => 0,
    );
    if ($fetch_error_message ne q{}) {
        print "[WARN] Could not fetch profile for $username: $fetch_error_message";
        return;
    }
    if ($fetch_attempts > 0) {
        my $msg = "[WARN] No profile data returned for $username";
        $msg = $msg . " after $fetch_attempts API key attempts";
        if ($empty_profile_responses > 0) {
            $msg = $msg . " ($empty_profile_responses empty responses)";
        }
        $msg = $msg . "\n";
        print $msg;
    }
    return;
}

sub _explore_profile_posts {
    my (%args) = @_;
    my $profile_data = $args{profile_data};
    my $username = $args{username};
    my $graph = $args{graph};
    my $api_keys = $args{api_keys};
    my $cache = $args{cache};
    my $cache_path = $args{cache_path};
    my $explored = $args{explored};
    my $depth = $args{depth};
    my $max_depth = $args{max_depth};
    my $posts_limit = $args{posts_limit};
    my $graph_path = $args{graph_path};
    my $profile_ttl_hours = $args{profile_ttl_hours};
    my $posts_ttl_hours = $args{posts_ttl_hours};

    for my $post (@{ $profile_data -> {latest_posts} || [] }) {
        _explore_post_relations(
            post        => $post,
            username    => $username,
            graph       => $graph,
            api_keys    => $api_keys,
            cache       => $cache,
            cache_path  => $cache_path,
            explored    => $explored,
            depth       => $depth,
            max_depth   => $max_depth,
            posts_limit => $posts_limit,
            graph_path  => $graph_path,
            profile_ttl_hours => $profile_ttl_hours,
            posts_ttl_hours   => $posts_ttl_hours,
        );
    }
    return;
}

sub _explore_post_relations {
    my (%args) = @_;
    my $post = $args{post};
    my $username = $args{username};
    my $graph = $args{graph};
    my @relations = (
        ['mentions', 'mention'],
        ['tagged_users', 'tag'],
        ['commenters', 'comment'],
    );
    for my $relation (@relations) {
        my ($relation_key, $interaction_type) = @{$relation};
        for my $related_user (@{ $post -> {$relation_key} || [] }) {
            if (!defined $related_user || $related_user eq q{} || $related_user eq $username) {
                next;
            }
            update_graph_node($graph, $related_user, full_name => $related_user);
            _upsert_interaction_edge(
                graph            => $graph,
                username         => $username,
                related_user     => $related_user,
                interaction_type => $interaction_type,
                post_id          => $post -> {post_id},
            );
            explore_users(
                username    => $related_user,
                api_keys    => $args{api_keys},
                cache       => $args{cache},
                cache_path  => $args{cache_path},
                graph       => $graph,
                explored    => $args{explored},
                depth       => $args{depth} + 1,
                max_depth   => $args{max_depth},
                posts_limit => $args{posts_limit},
                graph_path  => $args{graph_path},
                profile_ttl_hours => $args{profile_ttl_hours},
                posts_ttl_hours   => $args{posts_ttl_hours},
            );
        }
    }
    return;
}

sub _needs_profile_fetch {
    my ($profile_data, $profile_ttl_hours, $posts_ttl_hours) = @_;
    if (!$profile_data) {
        return 1;
    }

    my $profile_fresh = _is_profile_fresh($profile_data, $profile_ttl_hours);
    if (!$profile_fresh) {
        return 1;
    }

    my $account_type = $profile_data -> {account_type} // q{};
    if ($account_type eq 'Private') {
        return 0;
    }

    my $posts_fresh = _are_posts_fresh($profile_data, $posts_ttl_hours);
    if (!$posts_fresh) {
        return 1;
    }
    return 0;
}

sub _is_profile_fresh {
    my ($profile_data, $profile_ttl_hours) = @_;
    my $cache_meta = _cache_meta_hash($profile_data);
    my $cached_at = $cache_meta -> {profile_cached_at};
    return _is_cache_timestamp_fresh($cached_at, $profile_ttl_hours);
}

sub _are_posts_fresh {
    my ($profile_data, $posts_ttl_hours) = @_;
    if (!exists $profile_data -> {latest_posts}) {
        return 0;
    }
    my $cache_meta = _cache_meta_hash($profile_data);
    my $cached_at = $cache_meta -> {posts_cached_at};
    return _is_cache_timestamp_fresh($cached_at, $posts_ttl_hours);
}

sub _is_cache_timestamp_fresh {
    my ($cached_at, $ttl_hours) = @_;
    if (!defined $cached_at || $cached_at eq q{}) {
        return 0;
    }
    if (!defined $ttl_hours || $ttl_hours <= 0) {
        return 0;
    }
    if ($cached_at !~ /^\d+$/xms) {
        return 0;
    }
    my $ttl_seconds = _hours_to_seconds($ttl_hours);
    my $expires_at = $cached_at + $ttl_seconds;
    my $now_epoch = time;
    if ($now_epoch <= $expires_at) {
        return 1;
    }
    return 0;
}

sub _hours_to_seconds {
    my ($hours) = @_;
    return $hours * $SECONDS_PER_HOUR;
}

sub _cache_meta_hash {
    my ($profile_data) = @_;
    if (ref($profile_data -> {cache_meta}) eq 'HASH') {
        return $profile_data -> {cache_meta};
    }
    return {};
}

sub _set_cache_metadata {
    my ($profile_info, $profile_ttl_hours, $posts_ttl_hours) = @_;
    my $now_epoch = time;
    my $profile_expires_at = $now_epoch + _hours_to_seconds($profile_ttl_hours);
    my $cache_meta = {
        profile_cached_at => $now_epoch,
        profile_expires_at => $profile_expires_at,
        last_source => 'api',
    };

    if (exists $profile_info -> {latest_posts}) {
        my $posts_expires_at = $now_epoch + _hours_to_seconds($posts_ttl_hours);
        $cache_meta -> {posts_cached_at} = $now_epoch;
        $cache_meta -> {posts_expires_at} = $posts_expires_at;
    }

    $profile_info -> {cache_meta} = $cache_meta;
    return;
}

sub _mark_cache_source {
    my ($profile_data, $source) = @_;
    my $cache_meta = {};
    if (ref($profile_data -> {cache_meta}) eq 'HASH') {
        $cache_meta = $profile_data -> {cache_meta};
    }
    $cache_meta -> {last_source} = $source;
    $profile_data -> {cache_meta} = $cache_meta;
    return;
}

sub _upsert_interaction_edge {
    my (%args) = @_;
    my $graph = $args{graph};
    my $username = $args{username};
    my $related_user = $args{related_user};
    my $interaction_type = $args{interaction_type};
    my $post_id = $args{post_id};

    if (graph_has_edge($graph, $username, $related_user)) {
        my $edge_data = graph_get_edge($graph, $username, $related_user) || {};
        my $interactions = $edge_data -> {interactions} || [];
        push @{$interactions}, {
            type    => $interaction_type,
            post_id => $post_id,
        };
        $edge_data -> {interactions} = $interactions;
        $edge_data -> {weight} = ($edge_data -> {weight} // 1) + 1;
        graph_add_edge($graph, $username, $related_user, $edge_data);
        return;
    }

    graph_add_edge(
        $graph,
        $username,
        $related_user,
        {
            interactions => [
                {
                    type    => $interaction_type,
                    post_id => $post_id,
                }
            ],
            weight => 1,
        }
    );
    return;
}

sub compute_suspicious_scores {
    my ($cache, $graph, $main_user) = @_;

    for my $node (graph_nodes($graph)) {
        if ($node eq $main_user) {
            next;
        }
        if (graph_degree($graph, $node) != 1) {
            next;
        }
        if (!graph_has_edge($graph, $main_user, $node)) {
            next;
        }

        my $profile = $cache -> {$node};
        if (!$profile || !exists $profile -> {latest_posts}) {
            next;
        }

        my $posts = $profile -> {latest_posts} || [];
        my @post_dates;
        my $total_interactions = 0;

        for my $post (@{$posts}) {
            my $date_val = $post -> {date};
            my $parsed = _parse_date($date_val);
            if ($parsed) {
                push @post_dates, $parsed;
            }

            $total_interactions += ($post -> {likes} // 0) + ($post -> {comments} // 0);
        }

        @post_dates = sort { $a -> epoch <=> $b -> epoch } @post_dates;
        my $has_posts = 0;
        if (@post_dates) {
            $has_posts = 1;
        }

        my $temporal = 0.0;
        my $burstiness_score = 0.0;
        my $avg_interactions = 0.0;

        if ($has_posts) {
            $temporal = temporal_entropy(\@post_dates);
            $burstiness_score = burstiness(\@post_dates);
        }

        if (@{$posts}) {
            $avg_interactions = $total_interactions / scalar @{$posts};
        }

        my $name_entropy = entropy($profile -> {full_name} // q{});
        my $username_entropy = entropy($profile -> {username} // q{});
        my $followers = $profile -> {followers} // 0;

        my $engagement_ratio = 0.0;
        if ($followers > 0) {
            $engagement_ratio = $avg_interactions / $followers;
        }

        my $threshold = 1 / $ENGAGEMENT_THRESHOLD_DENOMINATOR;
        my $engagement_score = 1.0;
        if ($engagement_ratio < $threshold) {
            $engagement_score = $engagement_ratio / $threshold;
        }

        my $username_score = 1 / (1 + $username_entropy);
        my $name_score = 1 / (1 + $name_entropy);

        my $final_score = 0.0;
        if ($has_posts) {
            my $temporal_score_adj = 1 / (1 + ($temporal / 2));
            my $temporal_fuzzy = transform_burstiness($temporal_score_adj);
            my $burst_fuzzy = transform_burstiness($burstiness_score);
            my $engage_fuzzy = transform_burstiness($engagement_score);
            my $uname_fuzzy = transform_burstiness($username_score);
            my $name_fuzzy = transform_burstiness($name_score);

            $final_score = $SCORE_WEIGHT_BURST * $burst_fuzzy
                + $SCORE_WEIGHT_TEMPORAL * $temporal_fuzzy
                + $SCORE_WEIGHT_ENGAGEMENT * $engage_fuzzy
                + $SCORE_WEIGHT_USERNAME * $uname_fuzzy
                + $SCORE_WEIGHT_NAME * $name_fuzzy;
        } else {
            my $engage_fuzzy = transform_burstiness($engagement_score);
            my $uname_fuzzy = transform_burstiness($username_score);
            my $name_fuzzy = transform_burstiness($name_score);

            $final_score = $SCORE_NO_POSTS_ENGAGEMENT * $engage_fuzzy
                + $SCORE_NO_POSTS_USERNAME * $uname_fuzzy
                + $SCORE_NO_POSTS_NAME * $name_fuzzy;
        }

        $profile -> {suspicious_score} = {
            temporal_entropy => $temporal,
            name_entropy     => $name_entropy,
            username_entropy => $username_entropy,
            burstiness       => $burstiness_score,
            engagement_score => $engagement_score,
            final_score      => $final_score,
        };
    }
    return;
}

sub _parse_date {
    my ($value) = @_;
    if (!defined $value || $value eq q{}) {
        return;
    }

    my $parsed;
    my $parsed_ok = eval {
        if ($value =~ /^\d+(?:[.]\d+)?$/xms) {
            $parsed = localtime $value;
        }
        if ($value !~ /^\d+(?:[.]\d+)?$/xms) {
            my $normalized = $value;
            $normalized =~ s/Z$//xms;
            $normalized =~ s/T/ /xms;

            if ($normalized =~ /[.]\d+$/xms) {
                $normalized =~ s/[.]\d+$//xms;
            }

            $parsed = Time::Piece -> strptime(
                $normalized,
                '%Y-%m-%d %H:%M:%S'
            );
        }
        1;
    };
    if (!$parsed_ok) {
        return;
    }

    return $parsed;
}

1;
