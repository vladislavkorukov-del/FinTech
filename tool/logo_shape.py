"""Shape of a brand icon, so the app shows it in its own outline.

A round logo is shown as a circle with nothing behind it, a square one as a
square; anything else (a pin, a house, a wordmark) keeps a light tile so it
stays visible on dark themes.

    shape, display, backing = analyze(image)

`display` is the icon cropped to the logo. For a round logo everything
outside it is made transparent (this removes a white square some sites paint
around their round mark): outside the circle for a clean circle, outside the
mark's own outline when part of it sticks out (Пятёрочка's leaf, Сбер's tick).
Colors inside are untouched. `backing` is True when a round mark is mostly
see-through inside (a ring, a line drawing) and needs a light disc behind it
to stay visible on dark themes.
"""
from collections import deque

import numpy as np
from PIL import Image, ImageFilter

ROUND, SQUARE, TILE = 'round', 'square', 'tile'


def _background(content):
    """Pixels outside the logo: not content and connected to the border."""
    h, w = content.shape
    seen = np.zeros_like(content, dtype=bool)
    queue = deque()
    for x in range(w):
        for y in (0, h - 1):
            if not content[y, x] and not seen[y, x]:
                seen[y, x] = True
                queue.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if not content[y, x] and not seen[y, x]:
                seen[y, x] = True
                queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and not seen[ny, nx] and not content[ny, nx]:
                seen[ny, nx] = True
                queue.append((ny, nx))
    return seen


def _circle(side, scale=4):
    """Antialiased inscribed circle mask (0..255) for a square of `side`."""
    big = side * scale
    yy, xx = np.mgrid[0:big, 0:big]
    c = (big - 1) / 2
    r = big / 2 - scale * .5
    inside = ((xx - c) ** 2 + (yy - c) ** 2) <= r * r
    mask = Image.fromarray((inside * 255).astype(np.uint8)).resize((side, side), Image.LANCZOS)
    return np.asarray(mask).astype(np.float32) / 255


def _hull(mask):
    """Filled convex hull of the mark: a ring, a «5» or a tick on a white
    square still gives the outline of the whole mark."""
    ys, xs = np.nonzero(mask)
    points = sorted(set(zip(xs.tolist(), ys.tolist())))
    if len(points) < 3:
        return mask.copy()

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in points:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(points):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    hull = lower[:-1] + upper[:-1]
    from PIL import ImageDraw
    canvas = Image.new('L', (mask.shape[1], mask.shape[0]), 0)
    ImageDraw.Draw(canvas).polygon([(x + .5, y + .5) for x, y in hull], fill=255, outline=255)
    return np.asarray(canvas) > 127


def _erode(mask, steps):
    out = mask.copy()
    for _ in range(steps):
        out[1:, :] &= mask[:-1, :]
        out[:-1, :] &= mask[1:, :]
        out[:, 1:] &= mask[:, :-1]
        out[:, :-1] &= mask[:, 1:]
        mask = out.copy()
    return out


def analyze(image):
    im = image.convert('RGBA')
    a = np.asarray(im).astype(np.int32)
    h, w = a.shape[:2]
    m = max(1, round(min(w, h) * .02))
    corners = [a[m, m], a[m, w - 1 - m], a[h - 1 - m, m], a[h - 1 - m, w - 1 - m]]
    alpha = a[..., 3]
    if all(c[3] < 40 for c in corners):
        content = alpha >= 40
        backdrop = 'transparent'
    elif all(c[3] > 200 and min(c[:3]) > 232 for c in corners):
        far = np.abs(a[..., :3] - 255).max(axis=2) > 28
        content = (alpha >= 40) & far
        backdrop = 'white'
    else:
        return SQUARE, im, False  # a full-bleed colored square
    filled = _hull(content) if backdrop == 'white' else ~_background(content)
    ys, xs = np.nonzero(filled)
    if len(xs) == 0:
        return TILE, im, False
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    bw, bh = x1 - x0, y1 - y0
    if min(bw, bh) < min(w, h) * .3:
        return TILE, im, False
    if abs(bw - bh) <= .05 * max(bw, bh):
        side = max(bw, bh)
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        box = (round(cx - side / 2), round(cy - side / 2), round(cx - side / 2) + side, round(cy - side / 2) + side)
        crop = im.crop(box)
        region = np.zeros((side, side), dtype=bool)
        sub = filled[max(box[1], 0):min(box[3], h), max(box[0], 0):min(box[2], w)]
        oy, ox = max(-box[1], 0), max(-box[0], 0)
        region[oy:oy + sub.shape[0], ox:ox + sub.shape[1]] = sub
        circle = _circle(side) > .5
        iou = (region & circle).sum() / max((region | circle).sum(), 1)
        # A circle leaves the corners of its box empty (13 % in along the
        # diagonal is outside it); a rounded-square app icon fills them. One
        # filled corner is allowed for a mark that sticks out (a leaf, a tick).
        k = round(side * .13)
        corners = sum(bool(region[y, x]) for y in (k, side - 1 - k) for x in (k, side - 1 - k))
        if iou > .8 and corners <= 1:
            px = np.asarray(crop).astype(np.float32)
            if iou > .93:
                px[..., 3] *= _circle(side)
            else:
                # Keep what sticks out of the circle; drop only the backdrop
                # around the mark (one pixel in, so no light fringe remains).
                keep = _erode(region, max(1, side // 120))
                soft = Image.fromarray((keep * 255).astype(np.uint8)).filter(
                    ImageFilter.GaussianBlur(.6))
                px[..., 3] *= np.asarray(soft).astype(np.float32) / 255
            out = Image.fromarray(px.round().astype(np.uint8), 'RGBA')
            solid = (np.asarray(out)[..., 3] > 128) & region
            if backdrop == 'white':
                far = np.abs(np.asarray(out)[..., :3].astype(np.int32) - 255).max(axis=2) > 28
                solid &= far
            backing = solid.sum() / max(region.sum(), 1) < .45
            return ROUND, out, bool(backing)
        if region.mean() > .85:
            return SQUARE, crop, False
    if backdrop == 'white':
        return SQUARE, im, False  # the white square is the icon's own tile
    return TILE, im, False
