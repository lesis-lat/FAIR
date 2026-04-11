# FAIR - Fake Account Interaction Recognition (Perl)

FAIR is a Perl tool to detect potentially fake Instagram profiles based on interaction graphs and heuristic analysis.

## Features

- Uses Apify API to scrape public Instagram data
- Builds directed interaction graphs (mentions, tags, comments)
- Computes suspiciousness metrics (entropy, temporal entropy, burstiness, engagement)
- Generates an interactive HTML graph using D3.js
- Supports recursive profile exploration

## Requirements

- Perl 5.30+
- `keys.env` with one or more Apify API tokens (one per line or `KEY=value` format)

Install dependencies with your preferred CPAN workflow (for example `cpanm --installdeps .`).

## Usage

Run analysis:

```bash
perl fair.pl --username example_user --depth 2 --posts 3
```

Options:

- `--username`: Instagram handle to analyze (required)
- `--depth`: Number of recursive levels to follow (default: `2`)
- `--posts`: Number of posts to fetch per user (default: `3`)
- `--no-cache`: Ignore `cache.json` and re-fetch data
- `--suspicious-calc`: Compute suspicious scores and highlight suspicious nodes

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
│   ├── Graph.pm
│   ├── Metrics.pm
│   └── Visualization.pm
├── fair.pl
├── scripts/demo_graph.pl
├── cpanfile
└── README.md
```

## Disclaimer

This tool is intended for educational and research purposes only. Use responsibly and in compliance with Instagram's terms of service.
