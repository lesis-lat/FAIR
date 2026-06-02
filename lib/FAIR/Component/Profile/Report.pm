package FAIR::Component::Profile::Report;

use strict;
use warnings;
use Getopt::Long qw(GetOptionsFromArray);
use JSON::PP;

use FAIR::Cache qw(load_cache);

our $VERSION = '0.0.1';

sub new {
    my ($self, $message) = @_;
    my ($cache_path, $username);

    GetOptionsFromArray(
        $message,
        'cache-path=s' => \$cache_path,
        'username=s'   => \$username,
    );

    if (!defined $cache_path || $cache_path eq q{}) {
        return 0;
    }
    if (!defined $username || $username eq q{}) {
        return 0;
    }

    my $cache = load_cache($cache_path);
    if (!exists $cache -> {$username}) {
        return 0;
    }

    my $json_encoder = JSON::PP -> new;
    $json_encoder -> utf8;
    $json_encoder -> pretty;
    return $json_encoder -> encode($cache -> {$username});
}

1;
