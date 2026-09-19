#!/usr/bin/env python3
"""Cut 铜鹭 and 万签 from the batch-1 cast sheet for the two market boss levels.

MK17 needs the brass heron in three poses (巡守 / 举检查旗 / 展翼成搬运台) and MK18 needs the
yak in two poses plus the lantern ship it becomes. The sheet is *not* a clean 3x3 grid: the
heron row reaches y 619 and the yak row starts at y 613, and the column gaps wander, so a
uniform split slices feet off the herons and cuts the lantern rig off the yaks. Each figure is
instead grown from one probe pixel inside it, which yields that figure's exact box.

Background removal follows `cut_koukou.py`: a pixel is ground when it is near the sheet's cream
colour, and only ground reachable from the sheet border is made transparent, so cream trapped
inside a silhouette (a rope loop, the gap under a tray) stays opaque. Re-running must reproduce
the committed bytes exactly.
"""
from collections import deque
import hashlib
from pathlib import Path
import sys
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from cut_koukou import SOURCE, GROUND, TOLERANCE  # the shared ground colour and tolerance

PAD = 4
POSES = {
    'brass-heron-patrol': ('heron-v1', (283, 428)),
    'brass-heron-flag': ('heron-v1', (751, 399)),
    'brass-heron-platform': ('heron-v1', (1238, 403)),
    'wanqian-tags': ('wanqian-v1', (241, 817)),
    'wanqian-lanterns': ('wanqian-v1', (751, 810)),
    'lantern-ship': ('wanqian-v1', (1253, 819)),
}


def ink_mask(pixels):
    """Pixels that are far enough from the sheet's cream ground to belong to a figure."""
    return np.abs(pixels.astype(np.int16) - GROUND).sum(axis=2) > TOLERANCE


def outside(ink):
    """Ground pixels reachable from the sheet border; the rest of the ground is enclosed paint."""
    height, width = ink.shape
    seen = np.zeros_like(ink)
    queue = deque()
    def seed(x, y):
        if not ink[y, x] and not seen[y, x]:
            seen[y, x] = True
            queue.append((y, x))
    for x in range(width):
        seed(x, 0)
        seed(x, height - 1)
    for y in range(height):
        seed(0, y)
        seed(width - 1, y)
    while queue:
        y, x = queue.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < height and 0 <= nx < width and not ink[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                queue.append((ny, nx))
    return seen


def figure(ink, probe):
    """Grow one figure out of a probe pixel, returning its member mask and exact box."""
    height, width = ink.shape
    x, y = probe
    if not ink[y, x]:
        raise SystemExit(f'probe {probe} is not on a figure; the sheet no longer matches this tool')
    member = np.zeros_like(ink)
    member[y, x] = True
    queue = deque([(y, x)])
    while queue:
        cy, cx = queue.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = cy + dy, cx + dx
            if 0 <= ny < height and 0 <= nx < width and ink[ny, nx] and not member[ny, nx]:
                member[ny, nx] = True
                queue.append((ny, nx))
    ys, xs = np.nonzero(member)
    return member, (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)


def main() -> int:
    image = np.asarray(Image.open(SOURCE).convert('RGB'))
    ink = ink_mask(image)
    outside_ground = outside(ink)
    grown = {}
    for name, (folder, probe) in POSES.items():
        member, box = figure(ink, probe)
        for other in grown:
            if (member & grown[other]).any():
                raise SystemExit(f'{name} and {other} grew into one blob; the probe is wrong')
        grown[name] = member
        x0, y0, x1, y1 = box
        if min(x0, y0) < PAD or x1 > ink.shape[1] - PAD or y1 > ink.shape[0] - PAD:
            raise SystemExit(f'{name} touches the sheet edge, so its 4px transparent ring is lost')
        window = (slice(y0 - PAD, y1 + PAD), slice(x0 - PAD, x1 + PAD))
        # Opaque = this figure's own pixels, plus cream the border flood never reached. Foreign
        # ink (an antialiasing speck, the neighbour's shadow) is punched back out.
        enclosed = ~outside_ground[window] & ~ink[window]
        opaque = np.where(member[window] | enclosed, 255, 0).astype(np.uint8)
        sprite = Image.fromarray(np.dstack([image[window], opaque]), 'RGBA')
        target = ROOT / 'assets/runtime/market/characters' / folder / (name + '.png')
        target.parent.mkdir(parents=True, exist_ok=True)
        sprite.save(target)
        print(f"{target.relative_to(ROOT)} {sprite.size} " + hashlib.sha256(target.read_bytes()).hexdigest())
    return 0


if __name__ == '__main__':
    sys.exit(main())
