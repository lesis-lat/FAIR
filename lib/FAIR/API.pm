package FAIR::API;

use strict;
use warnings;
use Exporter 'import';
use Carp qw(croak);
use English qw(-no_match_vars);
use HTTP::Tiny;
use JSON::PP qw(decode_json encode_json);
use Time::HiRes qw(sleep);

our $VERSION = '0.1.0';

our @EXPORT_OK = qw(
  load_api_keys
  fetch_profile
  extract_profile
  fetch_posts
);

my $BASE_URL = 'https://api.apify.com/v2';
my $DEFAULT_POSTS_LIMIT = 1 + 2;
my $MAX_APIFY_RETRY_ATTEMPTS = 1 + 2;
my $APIFY_RETRY_STATUS = q{599};
my $INITIAL_RETRY_DELAY_SECONDS = 1;
sub load_api_keys {
    my ($path) = @_;
    if (!defined $path || !-e $path) {
        die "API keys file not found\n";
    }

    my @lines = _read_lines($path);
    my @keys;

    for my $line (@lines) {
        chomp $line;
        if ($line =~ /^\s*$/xms) {
            next;
        }
        if ($line =~ /^\s*\#/xms) {
            next;
        }

        my ($value) = split /=/xms, $line, 2;
        if (!defined $value) {
            $value = $line;
        }
        $value =~ s/^\s+//xms;
        $value =~ s/\s+$//xms;
        $value =~ s/^['"]//xms;
        $value =~ s/['"]$//xms;
        if ($value ne q{}) {
            push @keys, $value;
        }
    }

    if (!@keys) {
        die "No API keys found\n";
    }
    return \@keys;
}

sub fetch_profile {
    my ($username, $token) = @_;
    my $input_data = {
        directUrls  => ["https://www.instagram.com/$username/"],
        resultsType => 'details',
    };

    my $items = _run_actor_and_get_items('apify/instagram-scraper', $input_data, $token);
    if ($items && @{$items}) {
        return $items -> [0];
    }
    return;
}

sub extract_profile {
    my ($data) = @_;
    if (!$data || ref($data) ne 'HASH') {
        return;
    }

    my $account_type = 'Public';
    if ($data -> {private}) {
        $account_type = 'Private';
    }

    return {
        full_name    => $data -> {fullName}       // q{},
        username     => $data -> {username}       // q{},
        biography    => $data -> {biography}      // q{},
        account_type => $account_type,
        followers    => $data -> {followersCount} // 0,
        following    => $data -> {followsCount}   // 0,
        posts        => $data -> {postsCount}     // 0,
    };
}

sub fetch_posts {
    my ($username, $token, $limit) = @_;
    if (!defined $limit) {
        $limit = $DEFAULT_POSTS_LIMIT;
    }

    my $input_data = {
        username     => [$username],
        resultsLimit => $limit,
    };

    my $posts = _run_actor_and_get_items('nH2AHrwxeTRJoN5hX', $input_data, $token);
    $posts ||= [];

    my @formatted;
    for my $post (@{$posts}) {
        my @tagged_users = map { $_ -> {username} // q{} } @{ $post -> {taggedUsers} || [] };

        my %commenters;
        for my $comment (@{ $post -> {latestComments} || [] }) {
            my $owner = $comment -> {ownerUsername};
            if (!defined $owner || $owner eq q{}) {
                next;
            }
            $commenters{$owner} = 1;
        }

        push @formatted, {
            post_id      => $post -> {id}           // q{},
            date         => $post -> {timestamp}    // q{},
            location     => $post -> {locationName} // q{},
            mentions     => $post -> {mentions}     // [],
            tagged_users => \@tagged_users,
            commenters   => [sort keys %commenters],
            likes        => $post -> {likesCount}   // 0,
            comments     => scalar(@{ $post -> {latestComments} || [] }),
        };

        if (@formatted >= $limit) {
            last;
        }
    }

    return \@formatted;
}

sub _run_actor_and_get_items {
    my ($actor_id, $input_data, $token) = @_;
    if (!defined $token || $token eq q{}) {
        die "Missing API token\n";
    }

    my $http = HTTP::Tiny -> new(timeout => 60, agent => 'FAIR-Perl/1.0');
    my $actor_path = _normalize_actor_id($actor_id);

    my $sync_url = "$BASE_URL/acts/$actor_path/run-sync-get-dataset-items?token="
      . _url_escape($token);
    my $sync_resp = _post_sync_with_retry($http, $sync_url, $input_data);

    if (!$sync_resp -> {success}) {
        my $status = $sync_resp -> {status};
        my $reason = $sync_resp -> {reason};
        die "Apify actor call failed: $status $reason\n";
    }

    my $payload;
    my $decode_ok = eval {
        $payload = decode_json($sync_resp -> {content});
        1;
    };
    if (!$decode_ok) {
        croak "Apify response decode failed: $EVAL_ERROR";
    }

    return _extract_items_from_payload($payload);
}

sub _post_sync_with_retry {
    my ($http, $sync_url, $input_data) = @_;
    my $delay_seconds = $INITIAL_RETRY_DELAY_SECONDS;
    my $response;

    for my $attempt (1 .. $MAX_APIFY_RETRY_ATTEMPTS) {
        $response = $http -> post(
            $sync_url,
            {
                headers => { 'Content-Type' => 'application/json' },
                content => encode_json($input_data),
            }
        );

        if ($response -> {success}) {
            return $response;
        }

        my $status = $response -> {status};
        my $status_text = q{};
        if (defined $status) {
            $status_text = "$status";
        }
        if ($status_text ne $APIFY_RETRY_STATUS) {
            return $response;
        }
        if ($attempt >= $MAX_APIFY_RETRY_ATTEMPTS) {
            return $response;
        }

        print "[WARN] Apify returned status $status_text, retrying in $delay_seconds second(s)\n";
        my $sleep_result = sleep $delay_seconds;
        if (!defined $sleep_result) {
            return $response;
        }
        $delay_seconds = $delay_seconds * 2;
    }

    return $response;
}

sub _normalize_actor_id {
    my ($actor_id) = @_;
    $actor_id =~ s{/}{~}gxms;
    return $actor_id;
}

sub _url_escape {
    my ($text) = @_;
    $text //= q{};
    $text =~ s/([^\w.~-])/sprintf '%%%02X', ord $1/egxms;
    return $text;
}

sub _read_lines {
    my ($path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path
      or die "Cannot read $path: $OS_ERROR\n";
    my @lines = <$fh>;
    close $fh or die "Cannot close $path: $OS_ERROR\n";
    return @lines;
}

sub _extract_items_from_payload {
    my ($payload) = @_;
    if (ref($payload) eq 'ARRAY') {
        return $payload;
    }
    if (ref($payload) eq 'HASH') {
        if (ref($payload -> {data}) eq 'ARRAY') {
            return $payload -> {data};
        }
    }
    return [];
}

1;
