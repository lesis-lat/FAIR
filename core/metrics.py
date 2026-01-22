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
    hours = []
    for timestamp in timestamps:
        hours.append(timestamp.hour)
    counts = Counter(hours)
    total = len(timestamps)
    return -sum((count / total) * math.log2(count / total) for count in counts.values())


def burstiness(timestamps):
    if len(timestamps) < 2:
        return 0.0
    intervals = []
    for index in range(1, len(timestamps)):
        interval_hours = (timestamps[index] - timestamps[index - 1]).total_seconds() / 3600.0
        intervals.append(interval_hours)
    if not intervals:
        return 0.0
    mean = np.mean(intervals)
    std = np.std(intervals)
    if (std + mean) != 0:
        return (std - mean) / (std + mean)
    return 0.0


def transform_burstiness(value):
    return 1 - ((value + 1) / 2)


def fuzzy_low(value, lower_bound=0.0, upper_bound=0.5):
    if value <= lower_bound:
        return 1.0
    if value >= upper_bound:
        return 0.0
    return (upper_bound - value) / (upper_bound - lower_bound)


def fuzzy_high(value, lower_bound=0.5, upper_bound=1.0):
    if value <= lower_bound:
        return 0.0
    if value >= upper_bound:
        return 1.0
    return (value - lower_bound) / (upper_bound - lower_bound)
