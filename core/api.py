import os
from apify_client import ApifyClient
import json

def load_api_keys(path):
    if not os.path.exists(path):
        raise FileNotFoundError("API keys file not found")
    with open(path, "r", encoding="utf-8") as file:
        keys = []
        for line in file:
            if not line.strip():
                continue
            if line.startswith("#"):
                continue
            key_value = line.split("=")[-1].strip().strip('"\'')
            keys.append(key_value)
    if not keys:
        raise ValueError("No API keys found")
    return keys


def fetch_profile(username, token):
    client = ApifyClient(token)
    input_data = {"directUrls": [f"https://www.instagram.com/{username}/"], "resultsType": "details"}
    run = client.actor("apify/instagram-scraper").call(run_input=input_data)
    dataset = client.dataset(run["defaultDatasetId"])
    items = dataset.list_items().items
    if items:
        return items[0]
    return None


def extract_profile(data):
    if not data:
        return None
    account_type = "Public"
    if data.get("private"):
        account_type = "Private"
    return {
        "full_name": data.get("fullName", ""),
        "username": data.get("username", ""),
        "biography": data.get("biography", ""),
        "account_type": account_type,
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
    formatted_posts = []
    for post in posts:
        tagged_users = []
        for tag in post.get("taggedUsers", []):
            tagged_users.append(tag.get("username", ""))
        commenters = set()
        for comment in post.get("latestComments", []):
            owner_username = comment.get("ownerUsername")
            if not owner_username:
                continue
            commenters.add(owner_username)
        formatted_posts.append({
            "post_id": post.get("id", ""),
            "date": post.get("timestamp", ""),
            "location": post.get("locationName", ""),
            "mentions": post.get("mentions", []),
            "tagged_users": tagged_users,
            "commenters": sorted(commenters),
            "likes": post.get("likesCount", 0),
            "comments": len(post.get("latestComments", []))
        })
    return formatted_posts
