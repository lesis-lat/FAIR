package FAIR::Metrics;

use strict;
use warnings;
use Exporter 'import';
use Time::Seconds qw(ONE_HOUR);

our $VERSION = '0.1.0';
my $HALF = 1 / 2;

our @EXPORT_OK = qw(
  entropy
  temporal_entropy
  burstiness
  transform_burstiness
  fuzzy_low
  fuzzy_high
);

sub entropy {
    my ($text) = @_;
    if (!defined $text || $text eq q{}) {
        return 0.0;
    }

    my %counts;
    my @characters = unpack 'U*', $text;
    for my $character (@characters) {
        $counts{$character}++;
    }
    my $length = length $text;
    my $sum = 0.0;

    for my $count (values %counts) {
        my $p = $count / $length;
        $sum += $p * (_log2($p));
    }

    return -$sum;
}

sub temporal_entropy {
    my ($timestamps) = @_;
    if (!$timestamps || ref($timestamps) ne 'ARRAY' || !@{$timestamps}) {
        return 0.0;
    }

    my %counts;
    for my $ts (@{$timestamps}) {
        if (!defined $ts) {
            next;
        }
        my $hour = $ts -> hour;
        $counts{$hour}++;
    }

    my $total = 0;
    for my $count (values %counts) {
        $total += $count;
    }
    if ($total == 0) {
        return 0.0;
    }

    my $sum = 0.0;
    for my $count (values %counts) {
        my $p = $count / $total;
        $sum += $p * _log2($p);
    }

    return -$sum;
}

sub burstiness {
    my ($timestamps) = @_;
    if (!$timestamps || ref($timestamps) ne 'ARRAY' || @{$timestamps} < 2) {
        return 0.0;
    }

    my @intervals;
    my $previous_timestamp = $timestamps -> [0];
    for my $current_timestamp (@{$timestamps}[1 .. $#{$timestamps}]) {
        my $seconds = $current_timestamp -> epoch - $previous_timestamp -> epoch;
        push @intervals, $seconds / ONE_HOUR;
        $previous_timestamp = $current_timestamp;
    }

    if (!@intervals) {
        return 0.0;
    }

    my $mean = _mean(@intervals);
    my $std = _stddev(\@intervals, $mean);
    my $den = $std + $mean;

    if ($den == 0.0) {
        return 0.0;
    }
    return ($std - $mean) / $den;
}

sub transform_burstiness {
    my ($value) = @_;
    return 1 - (($value + 1) / 2);
}

sub fuzzy_low {
    my ($value, $lower_bound, $upper_bound) = @_;
    if (!defined $lower_bound) {
        $lower_bound = 0.0;
    }
    if (!defined $upper_bound) {
        $upper_bound = $HALF;
    }

    if ($value <= $lower_bound) {
        return 1.0;
    }
    if ($value >= $upper_bound) {
        return 0.0;
    }
    return ($upper_bound - $value) / ($upper_bound - $lower_bound);
}

sub fuzzy_high {
    my ($value, $lower_bound, $upper_bound) = @_;
    if (!defined $lower_bound) {
        $lower_bound = $HALF;
    }
    if (!defined $upper_bound) {
        $upper_bound = 1.0;
    }

    if ($value <= $lower_bound) {
        return 0.0;
    }
    if ($value >= $upper_bound) {
        return 1.0;
    }
    return ($value - $lower_bound) / ($upper_bound - $lower_bound);
}

sub _mean {
    my @values = @_;
    if (!@values) {
        return 0.0;
    }
    my $sum = 0.0;
    for my $value (@values) {
        $sum += $value;
    }
    return $sum / scalar @values;
}

sub _stddev {
    my ($values, $mean) = @_;
    if (ref($values) ne 'ARRAY' || !@{$values}) {
        return 0.0;
    }
    my $variance = 0.0;
    for my $value (@{$values}) {
        $variance += ($value - $mean) ** 2;
    }
    $variance /= scalar @{$values};
    return sqrt $variance;
}

sub _log2 {
    my ($x) = @_;
    if (!defined $x || $x <= 0) {
        return 0;
    }
    return log $x / log 2;
}

1;
