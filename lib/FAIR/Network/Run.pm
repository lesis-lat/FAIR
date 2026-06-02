package FAIR::Network::Run;

use strict;
use warnings;
use FAIR::Network::Compare;
use FAIR::Network::Help;
use FAIR::Network::Profile;

our $VERSION = '0.0.1';

sub new {
    my ($self, $message) = @_;

    if (!@{$message}) {
        return FAIR::Network::Help -> new([]);
    }

    for my $item (@{$message}) {
        if ($item eq '--help') {
            return FAIR::Network::Help -> new([]);
        }
        if ($item eq '--compare-with') {
            return FAIR::Network::Compare -> new($message);
        }
    }

    return FAIR::Network::Profile -> new($message);
}

1;
