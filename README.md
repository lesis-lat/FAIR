# FAIR - Fake Account Interaction Recognition (Perl)

FAIR is a Perl tool to detect potentially fake Instagram profiles based on interaction graphs and heuristic analysis.

## Features

- Uses Apify API to scrape public Instagram data
- Builds directed interaction graphs (mentions, tags, comments)
- Computes suspiciousness metrics (entropy, temporal entropy, burstiness, engagement)
- Generates an interactive HTML graph using D3.js
- Supports recursive profile exploration
- Compares two profiles and highlights whether they are connected
- Uses an FBP-style execution component for the CLI entry flow

## Requirements

- Perl 5.30+
- `keys.env` with one or more Apify API tokens (one per line or `KEY=value` format)

Install dependencies with your preferred CPAN workflow (for example `cpanm --installdeps .`).

## Usage

Run analysis:

```bash
perl fair.pl --username example_user --depth 2 --posts 3
```

Run comparison between two profiles:

```bash
perl fair.pl --username example_user --compare-with another_user --depth 2 --posts 3
```

Options:

- `--username`: Instagram handle to analyze (required)
- `--depth`: Number of recursive levels to follow (default: `2`)
- `--posts`: Number of posts to fetch per user (default: `3`)
- `--compare-with`: Second Instagram handle to compare against the main profile
- `--no-cache`: Ignore `cache.json` and re-fetch data
- `--suspicious-calc`: Compute suspicious scores and highlight suspicious nodes

When `--compare-with` is used, FAIR explores both profiles, merges the two
interaction graphs, prints a connection summary in the terminal, and writes a
comparison graph such as `graph_user_a_vs_user_b.html`.

## Demo

Generate a sample graph without API calls:

```bash
perl scripts/demo_graph.pl
```

## Project Structure

```text
.
├── lib/FAIR/
│   ├── API.pm
│   ├── Cache.pm
│   ├── Component/
│   │   ├── Graph/
│   │   │   ├── Connection.pm
│   │   │   ├── Merge.pm
│   │   │   └── Score.pm
│   │   ├── Profile/
│   │   │   ├── Build.pm
│   │   │   └── Report.pm
│   │   └── Visualization/
│   │       └── Render.pm
│   ├── Network/
│   │   ├── Compare.pm
│   │   ├── Help.pm
│   │   ├── Profile.pm
│   │   └── Run.pm
│   ├── Graph.pm
│   ├── Metrics.pm
│   └── Visualization.pm
├── fair.pl
├── scripts/demo_graph.pl
├── cpanfile
└── README.md
```

## FBP Entry Layer

The CLI entrypoint is routed through `FAIR::Network::Run`, which dispatches to
network features such as `FAIR::Network::Profile`,
`FAIR::Network::Compare`, and `FAIR::Network::Help`.

Those network packages orchestrate reusable components under
`FAIR::Component::*`, such as graph merge, graph scoring, profile build, and
HTML rendering. This is the current FBP split in the project:

- one package for one feature entrypoint
- one subroutine: `new`
- CLI-style message parsing with `GetOptionsFromArray`
- plain return values instead of direct exits

The existing `FAIR::*` modules remain the internal library layer used by that
component.

## Disclaimer

This tool is intended for educational and research purposes only. Use responsibly and in compliance with Instagram's terms of service.
