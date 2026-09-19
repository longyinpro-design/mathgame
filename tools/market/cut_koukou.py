#!/usr/bin/env python3
"""Re-cut 扣扣's two MK02 poses from the batch-1 cast sheet by border flood fill.

The cast sheet paints every figure on a flat cream ground, so the background is removed by
marking pixels that are near that ground colour *and* reachable from the crop border. Interior
cream stays opaque, which is why the parcel and the tail tag survive the cut. Re-running must
reproduce the committed bytes exactly.
"""
import hashlib
from collections import deque
from pathlib import Path
import sys
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT/'assets/source/market/cast-and-bosses-source-v1.png'
OUTPUT = ROOT/'assets/runtime/market/characters/koukou-v1'
GROUND = np.array([254, 251, 240], dtype=np.int16)
TOLERANCE = 60
POSES = {'tie-parcel': (512, 0, 1024, 245), 'waving': (1024, 0, 1536, 245)}

def cut(box):
    image = Image.open(SOURCE).convert('RGB').crop(box)
    pixels = np.asarray(image).astype(np.int16)
    height, width, _ = pixels.shape
    near = (np.abs(pixels - GROUND).sum(axis=2) <= TOLERANCE)
    seen = np.zeros_like(near)
    queue = deque()
    def seed(x, y):
        if near[y, x] and not seen[y, x]:
            seen[y, x] = True; queue.append((y, x))
    for x in range(width):
        seed(x, 0); seed(x, height-1)
    for y in range(height):
        seed(0, y); seed(width-1, y)
    while queue:
        y, x = queue.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y+dy, x+dx
            if 0 <= ny < height and 0 <= nx < width and near[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True; queue.append((ny, nx))
    alpha = np.where(seen, 0, 255).astype(np.uint8)
    sprite = Image.fromarray(np.dstack([np.asarray(image), alpha]), 'RGBA')
    ys, xs = np.nonzero(alpha)
    return sprite.crop((int(xs.min())-4, int(ys.min())-4, int(xs.max())+5, int(ys.max())+5))

def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, box in POSES.items():
        sprite = cut(box)
        target = OUTPUT/(name+'.png')
        sprite.save(target)
        print(f"{target.relative_to(ROOT)} {sprite.size} "+hashlib.sha256(target.read_bytes()).hexdigest())
    return 0

if __name__ == '__main__':
    sys.exit(main())
