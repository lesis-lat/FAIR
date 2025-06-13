import os
import json

def load_cache(path):
    if not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as file:
        try:
            return json.load(file)
        except json.JSONDecodeError:
            return {}


def save_cache(path, data):
    with open(path, "w", encoding="utf-8") as file:
        json.dump(data, file, indent=4)