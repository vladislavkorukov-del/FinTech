"""Features of an operation for the Finora classifier.

MUST stay identical to lib/features/finora_ai/inference/features.dart.
The parity fixtures written by train.py are checked by a Dart test.
"""

import math
import re
from dataclasses import dataclass
from datetime import date

# Version of the feature pipeline. A model records the version it was trained
# with; the app computes features for that version (or refuses the model).
#   1 — merchant 3-grams, words, kind, amount bucket, weekday, month, account
#   2 — plus amount bucket × kind («ak:»): +1.2 pp accuracy and +2.0 pp
#       top-3 on held-out merchants, better on 6 of 6 splits (synthetic data)
PREPROCESSING_VERSION = 2

_NON_WORD = re.compile(r"[^a-zа-я0-9]+")
_DIGITS = re.compile(r"\d+")
_ALL_DIGITS = re.compile(r"^\d+$")


@dataclass
class TransactionInput:
    merchant: str
    description: str
    amount_minor: int
    kind: str  # 'expense' | 'income'
    account_type: str
    date: date


def normalize(s: str) -> str:
    return _NON_WORD.sub(" ", s.lower().replace("ё", "е")).strip()


def fnv1a(s: str) -> int:
    h = 0x811C9DC5
    for b in s.encode("utf-8"):
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def amount_bucket(minor: int) -> int:
    rub = abs(minor) // 100
    if rub < 1:
        return 0
    return max(0, min(20, rub.bit_length() - 1))


def tokens(t: TransactionInput, version: int = PREPROCESSING_VERSION) -> list[str]:
    merchant = normalize(t.merchant)
    text = normalize(f"{t.merchant} {t.description}")
    out: list[str] = []
    m = f" {_DIGITS.sub('0', merchant)} "
    for i in range(0, len(m) - 2):
        out.append("c3:" + m[i : i + 3])
    for w in text.split(" "):
        if len(w) >= 2 and not _ALL_DIGITS.match(w):
            out.append("w:" + w)
    out.append(f"k:{t.kind}")
    out.append(f"a:{amount_bucket(t.amount_minor)}")
    out.append(f"d:{t.date.isoweekday()}")
    out.append(f"m:{t.date.month}")
    out.append(f"t:{t.account_type}")
    if version >= 2:
        out.append(f"ak:{t.kind}:{amount_bucket(t.amount_minor)}")
    return out


def vector(
    t: TransactionInput, buckets: int, version: int = PREPROCESSING_VERSION
) -> tuple[list[int], float]:
    idx = sorted({fnv1a(s) % buckets for s in tokens(t, version)})
    return idx, (1 / math.sqrt(len(idx)) if idx else 0.0)
