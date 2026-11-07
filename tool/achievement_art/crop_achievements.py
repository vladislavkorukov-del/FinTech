"""Cuts the owner's achievement sheets (3×5 Finora pictures each) into
illustrations without the caption → assets/finora/achievements/*.webp."""
import os
from PIL import Image, ImageDraw

def bounds(im):
    w, h = im.size
    bg = im.getpixel((3, 3))
    def far(p): return sum(abs(a - b) for a, b in zip(p, bg)) > 45
    cols = [sum(far(im.getpixel((x, y))) for y in range(0, h, 4)) for x in range(w)]
    rows = [sum(far(im.getpixel((x, y))) for x in range(0, w, 4)) for y in range(h)]
    def split(v, n):
        # n tiles: cut at the n-1 lowest valleys between them.
        size = len(v) // n
        cuts = []
        for k in range(1, n):
            lo, hi = k * size - size // 4, k * size + size // 4
            cuts.append(min(range(lo, hi), key=lambda i: v[i]))
        edges = [0] + cuts + [len(v)]
        out = []
        for a, b in zip(edges, edges[1:]):
            peak = max(v[a:b])
            xs = [i for i in range(a, b) if v[i] > peak * .5]
            out.append((xs[0], xs[-1]))
        return out
    return split(cols, 3), split(rows, 5)

names = {
    'sheet1.png': ['limit_kept', 'expenses_control', 'income_grows',
                   'balance_plus', 'debt_closed', 'subs_control',
                   'payment_on_time', 'report_ready', 'analyst',
                   'category_master', 'month_plan', 'finance_zen',
                   'cashback', 'invest_started', 'budget_master'],
    'sheet2.png': ['first_step', 'first_record', 'first_income',
                   'first_expense', 'budget_created', 'categories_set',
                   'accounts_added', 'week_tracking', 'month_discipline',
                   'seven_days', 'piggy_opened', 'goal_set',
                   'goal_done', 'safety_cushion', 'no_spend_day'],
}
out = '../../assets/finora/achievements'
os.makedirs(out, exist_ok=True)
for sheet, ids in names.items():
    im = Image.open(sheet).convert('RGB')
    cols, rows = bounds(im)
    k = 0
    for y0, y1 in rows:
        for x0, x1 in cols:
            w, h = x1 - x0, y1 - y0
            # The caption takes the top quarter; the art is below it.
            # Two-line captions reach lower.
            top = .34 if ids[k] in ('expenses_control', 'subs_control') else .25
            art = im.crop((x0 + int(w * .04), y0 + int(h * top), x1 - int(w * .04), y1 - int(h * .04)))
            art = art.resize((512, round(512 * art.size[1] / art.size[0])), Image.LANCZOS)
            art.save(f'{out}/{ids[k]}.webp', 'WEBP', quality=88, method=6)
            k += 1
    print(sheet, cols, rows)
