"""Turn a Finora JSON backup into labelled rows for train.py --extra.

    python3 tool/finora_ai/from_backup.py finora-backup.json out.csv

Runs locally; nothing is sent anywhere. The output holds the person's own
payees and sums — keep it private and never commit it.

A row is written for every posted expense or income with a payee whose
category maps to exactly one canonical class. The mapping is read from the
app's own lib/features/finora_ai/classification/category_mapper.dart, so the
app and the training data agree on what «Продукты» or «Еда» means. Transfers,
pending/cancelled operations, empty payees and categories that fit no class
(or several) are skipped and counted.
"""

from __future__ import annotations

import csv
import json
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from dataset import CLASSES, INCOME, ROOT  # noqa: E402

MAPPER = ROOT / "lib/features/finora_ai/classification/category_mapper.dart"
_ENTRY = re.compile(r"'(\w+)': \[(.*?)\],", re.S)
_PATTERN = re.compile(r"r'([^']*)'")


def patterns() -> dict[str, list[re.Pattern]]:
    """Canonical class → name patterns, from the Dart mapper."""
    text = MAPPER.read_text(encoding="utf-8")
    body = text[text.index("patterns = <String, List<String>>{"):]
    body = body[: body.index("};")]
    out = {}
    for name, items in _ENTRY.findall(body):
        out[name] = [re.compile(p, re.I) for p in _PATTERN.findall(items)]
    missing = set(CLASSES) - set(out)
    if missing:
        raise SystemExit(f"category_mapper.dart lacks classes: {sorted(missing)}")
    return out


def class_for(name: str, kind: str, table) -> str | None:
    """The canonical class of a category name, or None when no class or
    several classes fit (same rule as CategoryMapper, from the other side)."""
    clean = name.lower().replace("ё", "е").strip()
    hits = []
    for cls, pats in table.items():
        if (cls in INCOME) != (kind == "income"):
            continue
        for i, p in enumerate(pats):
            if p.search(clean):
                hits.append((i, cls))
                break
    if not hits:
        return None
    best = min(i for i, _ in hits)
    top = [c for i, c in hits if i == best]
    return top[0] if len(top) == 1 else None


def convert(backup: Path, out: Path) -> Counter:
    raw = json.loads(backup.read_text(encoding="utf-8"))
    data = raw.get("data", raw)
    table = patterns()
    categories = {c["id"]: c for c in data.get("categories", [])}
    accounts = {a["id"]: a.get("type", "") for a in data.get("accounts", [])}
    stats = Counter()
    with out.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["merchant", "description", "amount_minor", "kind",
                    "account_type", "date", "label"])
        for e in data.get("entries", []):
            kind = e.get("kind")
            if kind not in ("expense", "income"):
                stats["skipped: transfer"] += 1
                continue
            if e.get("status", "posted") != "posted":
                stats["skipped: not posted"] += 1
                continue
            payee = (e.get("payee") or "").strip()
            if not payee:
                stats["skipped: no payee"] += 1
                continue
            category = categories.get(e.get("categoryId"))
            label = class_for(category["name"], kind, table) if category else None
            if label is None:
                stats["skipped: category fits no single class"] += 1
                continue
            w.writerow([payee, (e.get("note") or "").strip(),
                        int(e["amountMinor"]), kind,
                        accounts.get(e.get("accountId"), ""),
                        str(e["date"])[:10], label])
            stats["written"] += 1
    return stats


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    stats = convert(Path(sys.argv[1]), Path(sys.argv[2]))
    for k, v in sorted(stats.items()):
        print(f"{k}: {v}")


if __name__ == "__main__":
    main()
