"""Cuts the owner's Finora pictures (src/*.png) to the tile: the rounded
square without the white/black margins, corners transparent → out/*.png."""
import glob, os, sys
from PIL import Image, ImageDraw

def diff(a, b):
    return sum(abs(x - y) for x, y in zip(a, b))

def crop(path, thr=60):
    im = Image.open(path).convert('RGB'); w, h = im.size
    corners = [im.getpixel(p) for p in ((1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2))]
    bg = tuple(sum(c) // 4 for c in zip(*corners))
    px = im.load()
    def colhit(x): return sum(1 for y in range(0, h, 3) if diff(px[x, y], bg) > thr) > h / 6
    def rowhit(y): return sum(1 for x in range(0, w, 3) if diff(px[x, y], bg) > thr) > w / 6
    x0 = next(x for x in range(w) if colhit(x)); x1 = next(x for x in range(w - 1, -1, -1) if colhit(x))
    y0 = next(y for y in range(h) if rowhit(y)); y1 = next(y for y in range(h - 1, -1, -1) if rowhit(y))
    ds = []
    for cx, cy, sx, sy in [(x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)]:
        d = 0
        while d < 400 and diff(px[cx + sx * d, cy + sy * d], bg) <= thr: d += 1
        ds.append(d)
    r = int(sorted(ds)[1] / (1 - 0.7071))
    inset = 3
    tile = im.crop((x0 + inset, y0 + inset, x1 - inset, y1 - inset)).convert('RGBA')
    W, H = tile.size; S = 4
    m = Image.new('L', (W * S, H * S), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, W * S - 1, H * S - 1), radius=max(8, r - inset) * S, fill=255)
    tile.putalpha(m.resize((W, H), Image.LANCZOS))
    k = 480 / max(W, H)
    return tile.resize((round(W * k), round(H * k)), Image.LANCZOS)

if __name__ == '__main__':
    special = {'dream_savings': 18}
    os.makedirs('out', exist_ok=True)
    for f in sorted(glob.glob('src/*.png')):
        n = os.path.basename(f)[:-4]
        crop(f, special.get(n, 60)).save(f'out/{n}.png')
