import math
from collections import Counter
import numpy as np

def entropy(text):
    if not text:
        return 0.0
    counts = Counter(text)
    length = len(text)
    return -sum((count / length) * math.log2(count / length) for count in counts.values())


def temporal_entropy(timestamps):
    if not timestamps:
        return 0.0
    hours = [dt.hour for dt in timestamps]
    counts = Counter(hours)
    total = len(timestamps)
    return -sum((count / total) * math.log2(count / total) for count in counts.values())


def burstiness(timestamps):
    if len(timestamps) < 2:
        return 0.0
    intervals = [(timestamps[i] - timestamps[i - 1]).total_seconds() / 3600.0 for i in range(1, len(timestamps))]
    if not intervals:
        return 0.0
    mean = np.mean(intervals)
    std = np.std(intervals)
    return (std - mean) / (std + mean) if (std + mean) != 0 else 0.0


def transform_burstiness(value):
    return 1 - ((value + 1) / 2)


def fuzzy_low(value, a=0.0, b=0.5):
    if value <= a:
        return 1.0
    elif value >= b:
        return 0.0
    return (b - value) / (b - a)


def fuzzy_high(value, a=0.5, b=1.0):
    if value <= a:
        return 0.0
    elif value >= b:
        return 1.0
    return (value - a) / (b - a)