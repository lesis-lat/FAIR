# FAIR - Fake Account Interaction Recognition

FAIR is a Python tool to detect potentially fake Instagram profiles based on interaction graphs and heuristic analysis.

![](fake_profile_detection_steps.gif) 

## Features

* Uses Apify API to scrape public Instagram data
* Builds interaction graphs using NetworkX
* Analyzes user profiles using entropy, burstiness, and engagement metrics
* Visualizes results with an interactive HTML graph using mpld3
* Supports recursive profile exploration

## Installation

### Requirements

Python 3.8+

Install dependencies:

```bash
pip install -r requirements.txt
```

## Usage

Run the analysis with:

```bash
python main.py --username example_user --depth 2 --posts 3
```

### Options

* `--username`: Instagram handle to analyze (required)
* `--depth`: Number of recursive levels to follow (default: 2)
* `--posts`: Number of posts to fetch per user (default: 3)
* `--no-cache`: Ignore previously saved data and re-fetch everything

## Project Structure

```
.
├── core/
│   ├── __init__.py
│   ├── api.py
│   ├── cache.py
│   ├── metrics.py
├── main.py
├── requirements.txt
├── README.md
```

## Notes

* You must create a `keys.env` file containing your Apify API keys.
* Only public Instagram profiles can be analyzed.

## Disclaimer

This tool is intended for educational and research purposes only. Use responsibly and in compliance with Instagram's terms of service.