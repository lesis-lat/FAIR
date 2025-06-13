import os
from apify_client import ApifyClient
import json

def load_api_keys(path):
    if not os.path.exists(path):
        raise FileNotFoundError("API keys file not found")
    with open(path, "r", encoding="utf-8") as file:
        keys = [line.split("=")[-1].strip().strip('"\'') for line in file if line.strip() and not line.startswith("#")]
    if not keys:
        raise ValueError("No API keys found")
    return keys


def fetch_profile(username, token):
    client = ApifyClient(token)
    input_data = {"directUrls": [f"https://www.instagram.com/{username}/"], "resultsType": "details"}
    run = client.actor("apify/instagram-scraper").call(run_input=input_data)
    dataset = client.dataset(run["defaultDatasetId"])
    items = dataset.list_items().items
    return items[0] if items else None


def extract_profile(data):
    if not data:
        return None
    return {
        "full_name": data.get("fullName", ""),
        "username": data.get("username", ""),
        "biography": data.get("biography", ""),
        "account_type": "Private" if data.get("private") else "Public",
        "followers": data.get("followersCount", 0),
        "following": data.get("followsCount", 0),
        "posts": data.get("postsCount", 0)
    }


def fetch_posts(username, token, limit=3):
    client = ApifyClient(token)
    input_data = {"username": [username], "resultsLimit": limit}
    run = client.actor("nH2AHrwxeTRJoN5hX").call(run_input=input_data)
    dataset = client.dataset(run["defaultDatasetId"])
    posts = list(dataset.iterate_items())[:limit]
    return [{
        "post_id": p.get("id", ""),
        "date": p.get("timestamp", ""),
        "location": p.get("locationName", ""),
        "mentions": p.get("mentions", []),
        "tagged_users": [tag.get("username", "") for tag in p.get("taggedUsers", [])],
        "commenters": sorted({c.get("ownerUsername") for c in p.get("latestComments", []) if c.get("ownerUsername")}),
        "likes": p.get("likesCount", 0),
        "comments": len(p.get("latestComments", []))
    } for p in posts]