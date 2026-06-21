#!/usr/bin/env python3
"""Extract dominant color from a planet texture image using K-means clustering."""

import os
os.environ["OPENCV_LOG_LEVEL"] = "SILENT"

import cv2
import numpy as np
import sys


def get_dominant_color(image_path, sample_size=256):
    """Extract dominant color from center of image using K-means."""
    img = cv2.imread(image_path)
    if img is None:
        raise FileNotFoundError(f"Image not found: {image_path}")

    h, w = img.shape[:2]
    # Center crop
    cx, cy = w // 2, h // 2
    half = sample_size // 2
    y1, y2 = max(0, cy - half), min(h, cy + half)
    x1, x2 = max(0, cx - half), min(w, cx + half)
    region = img[y1:y2, x1:x2]

    if region.size == 0:
        return [0, 0, 0]

    # Flatten and filter black pixels
    pixels = region.reshape((-1, 3))
    non_black = pixels[np.any(pixels > 15, axis=1)]
    if non_black.shape[0] == 0:
        non_black = pixels

    region = np.float32(non_black)
    if region.shape[0] < 3:
        return [int(x) for x in np.mean(region, axis=0)]

    # K-means to find dominant color
    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 10, 1.0)
    K = min(5, region.shape[0])
    _, labels, centers = cv2.kmeans(region, K, None, criteria, 10, cv2.KMEANS_RANDOM_CENTERS)
    counts = np.bincount(labels.flatten())
    dominant = centers[np.argmax(counts)]

    # BGR -> RGB -> hex
    r, g, b = int(dominant[2]), int(dominant[1]), int(dominant[0])
    return f"#{r:02x}{g:02x}{b:02x}"


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("#1a6b4a", file=sys.stdout)
        sys.exit(0)

    image_path = sys.argv[1]
    try:
        color = get_dominant_color(image_path)
        print(color, file=sys.stdout)
    except Exception:
        print("#1a6b4a", file=sys.stdout)
