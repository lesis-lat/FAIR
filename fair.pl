#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";

use FAIR::Network::Run;

our $VERSION = '0.1.0';

my @result = FAIR::Network::Run -> new([@ARGV]);

for my $item (@result) {
    if (!defined $item) {
        next;
    }
    print $item;
}
