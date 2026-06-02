package FAIR::Network::Help;

use strict;
use warnings;
use Readonly;

our $VERSION = '0.0.1';

Readonly my $HELP_COMMAND_WIDTH => 32;

sub new {
    my ($self, $message) = @_;
    return join "\n",
      q{},
      'Core Commands',
      '=============',
      sprintf(
        '  %-*s %s',
        $HELP_COMMAND_WIDTH,
        'Command',
        'Description'
      ),
      sprintf(
        '  %-*s %s',
        $HELP_COMMAND_WIDTH,
        '-------',
        '-----------'
      ),
      sprintf(
        '  %-*s %s',
        $HELP_COMMAND_WIDTH,
        '--username <handle>',
        'Analyze one Instagram profile'
      ),
      sprintf(
        '  %-*s %s',
        $HELP_COMMAND_WIDTH,
        '--compare-with <handle>',
        'Compare a second profile against --username'
      ),
      sprintf(
        '  %-*s %s',
        $HELP_COMMAND_WIDTH,
        '--depth <number>',
        'Set recursion depth'
      ),
      sprintf(
        '  %-*s %s',
        $HELP_COMMAND_WIDTH,
        '--posts <number>',
        'Set fetched posts per profile'
      ),
      sprintf(
        '  %-*s %s',
        $HELP_COMMAND_WIDTH,
        '--suspicious-calc',
        'Calculate suspiciousness scores'
      ),
      sprintf(
        '  %-*s %s',
        $HELP_COMMAND_WIDTH,
        '--no-cache',
        'Ignore local cache and fetch again'
      ),
      sprintf(
        '  %-*s %s',
        $HELP_COMMAND_WIDTH,
        '--profile-ttl-hours <number>',
        'Set profile cache lifetime'
      ),
      sprintf(
        '  %-*s %s',
        $HELP_COMMAND_WIDTH,
        '--posts-ttl-hours <number>',
        'Set posts cache lifetime'
      ),
      sprintf(
        '  %-*s %s',
        $HELP_COMMAND_WIDTH,
        '--help',
        'Show this help message'
      ),
      q{},
      'Examples',
      '========',
      'perl fair.pl --username example_user --depth 2 --posts 3',
      'perl fair.pl --username profile_a --compare-with profile_b',
      q{};
}

1;
