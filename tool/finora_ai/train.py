"""Train, evaluate and export the Finora transaction classifier.

    python3 tool/finora_ai/train.py [--extra data.csv] [--version 1.0.0]

Model: multinomial logistic regression (softmax) over hashed features
(features.py), trained with mini-batch Adam and L2. Exported as
assets/ai/finora_classifier.json: int8 weights with a per-class scale, float
biases, the class list and a version. Also writes metrics and the parity
fixtures used by the Dart test.
"""

from __future__ import annotations

import argparse
import base64
import json
import random
import sys
from datetime import date, datetime, timezone
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from dataset import CLASSES, ROOT, load_csv, synthetic  # noqa: E402
from features import PREPROCESSING_VERSION, TransactionInput, vector  # noqa: E402

BUCKETS = 1 << 13
FORMAT = "finora-linear-v1"
# Version of the model file layout (fields below); the app accepts 1–2.
SCHEMA_VERSION = 2
# Held-out-merchant splits for the reported mean ± spread (the shipped model
# is trained on the first split).
SPLIT_SEEDS = (3, 11, 29, 41, 53, 67)


def balance(rows, cap=1100, floor=450, seed=5):
    """Caps big classes and resamples small ones so no class dominates."""
    rnd = random.Random(seed)
    by = {}
    for r in rows:
        by.setdefault(r[1], []).append(r)
    out = []
    for _label, items in by.items():
        if len(items) > cap:
            items = rnd.sample(items, cap)
        elif len(items) < floor:
            items = items + [rnd.choice(items) for _ in range(floor - len(items))]
        out += items
    return out


def featurize(rows):
    return [vector(r[0], BUCKETS) for r in rows]


def batch_matrix(feats, idx):
    x = np.zeros((len(idx), BUCKETS), dtype=np.float32)
    for r, i in enumerate(idx):
        cols, val = feats[i]
        x[r, cols] = val
    return x


def softmax(z):
    z = z - z.max(axis=1, keepdims=True)
    e = np.exp(z)
    return e / e.sum(axis=1, keepdims=True)


def train(feats, y, epochs=18, lr=0.05, l2=1e-5, batch=512, seed=1, verbose=True):
    rng = np.random.default_rng(seed)
    n, c = len(feats), len(CLASSES)
    w = np.zeros((BUCKETS, c), dtype=np.float32)
    b = np.zeros(c, dtype=np.float32)
    m_w = np.zeros_like(w); v_w = np.zeros_like(w)
    m_b = np.zeros_like(b); v_b = np.zeros_like(b)
    t = 0
    for epoch in range(epochs):
        order = rng.permutation(n)
        loss = 0.0
        for s in range(0, n, batch):
            idx = order[s : s + batch]
            x = batch_matrix(feats, idx)
            p = softmax(x @ w + b)
            target = np.zeros_like(p)
            target[np.arange(len(idx)), y[idx]] = 1
            loss -= np.log(p[np.arange(len(idx)), y[idx]] + 1e-9).sum()
            g = (p - target) / len(idx)
            gw = x.T @ g + l2 * w
            gb = g.sum(axis=0)
            t += 1
            for param, grad, m, v in ((w, gw, m_w, v_w), (b, gb, m_b, v_b)):
                m *= 0.9; m += 0.1 * grad
                v *= 0.999; v += 0.001 * grad * grad
                mh = m / (1 - 0.9 ** t); vh = v / (1 - 0.999 ** t)
                param -= lr * mh / (np.sqrt(vh) + 1e-8)
        if verbose:
            print(f"epoch {epoch + 1:2d}  loss {loss / n:.4f}")
    return w, b


def predict(feats, w, b):
    out = np.zeros((len(feats), len(CLASSES)), dtype=np.float32)
    for s in range(0, len(feats), 2048):
        idx = list(range(s, min(s + 2048, len(feats))))
        out[s : s + len(idx)] = softmax(batch_matrix(feats, idx) @ w + b)
    return out


def quantize(w):
    scale = np.abs(w).max(axis=0) / 127.0
    scale[scale == 0] = 1.0
    q = np.clip(np.round(w / scale), -127, 127).astype(np.int8)
    return q, scale


def metrics(prob, y):
    pred = prob.argmax(axis=1)
    top3 = np.argsort(-prob, axis=1)[:, :3]
    per_class = {}
    for c, name in enumerate(CLASSES):
        tp = int(((pred == c) & (y == c)).sum())
        fp = int(((pred == c) & (y != c)).sum())
        fn = int(((pred != c) & (y == c)).sum())
        prec = tp / (tp + fp) if tp + fp else 0.0
        rec = tp / (tp + fn) if tp + fn else 0.0
        f1 = 2 * prec * rec / (prec + rec) if prec + rec else 0.0
        per_class[name] = {"precision": round(prec, 4), "recall": round(rec, 4),
                           "f1": round(f1, 4), "support": int((y == c).sum())}
    return {
        "accuracy": round(float((pred == y).mean()), 4),
        "top3_accuracy": round(float((top3 == y[:, None]).any(axis=1).mean()), 4),
        "macro_f1": round(float(np.mean([v["f1"] for v in per_class.values()
                                         if v["support"]])), 4),
        "per_class": per_class,
    }


FIXTURES = [
    ("Пятёрочка", 45000, "expense"), ("MAGNIT MM KOSTROMA", 123400, "expense"),
    ("Яндекс Go", 38900, "expense"), ("Шоколадница", 65000, "expense"),
    ("Spotify", 16900, "expense"), ("Лукойл АЗС", 250000, "expense"),
    ("Аптека Ригла", 54000, "expense"), ("Wildberries", 189000, "expense"),
    ("Четыре лапы", 99000, "expense"), ("Зарплата", 9000000, "income"),
    ("Проценты по вкладу", 120000, "income"), ("ЖКХ оплата", 420000, "expense"),
]


def split(rows, seed):
    """Validation holds out whole merchants: the model never saw them, so the
    score shows how it handles new places, not memorised names."""
    names = sorted({r[2] for r in rows})
    random.Random(seed).shuffle(names)
    held = set(names[: int(len(names) * 0.15)])
    train_rows = [r for r in rows if r[2] not in held]
    val_rows = [r for r in rows if r[2] in held]
    random.Random(seed).shuffle(train_rows)
    return train_rows, val_rows


def cross_split(rows):
    """Mean and spread over several held-out-merchant splits: one split's
    luck is about ±7 pp, larger than most feature changes."""
    scores = []
    for seed in SPLIT_SEEDS:
        tr, va = split(rows, seed)
        y_tr = np.array([CLASSES.index(r[1]) for r in tr])
        y_va = np.array([CLASSES.index(r[1]) for r in va])
        w, b = train(featurize(tr), y_tr, verbose=False)
        q, scale = quantize(w)
        m = metrics(predict(featurize(va), q.astype(np.float32) * scale, b), y_va)
        scores.append([m["accuracy"], m["top3_accuracy"], m["macro_f1"]])
    a = np.array(scores)
    return {
        "splits": len(SPLIT_SEEDS),
        **{f"{k}_mean": round(float(a[:, i].mean()), 4)
           for i, k in enumerate(("accuracy", "top3_accuracy", "macro_f1"))},
        **{f"{k}_std": round(float(a[:, i].std()), 4)
           for i, k in enumerate(("accuracy", "top3_accuracy", "macro_f1"))},
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--extra", type=Path, action="append", default=[])
    ap.add_argument("--version", default="1.1.0")
    ap.add_argument("--quick", action="store_true",
                    help="skip the cross-split evaluation")
    args = ap.parse_args()

    rows = balance(synthetic())
    for p in args.extra:
        rows += load_csv(p)
    train_rows, val_rows = split(rows, SPLIT_SEEDS[0])
    print(f"train {len(train_rows)}  validation {len(val_rows)}")
    y_train = np.array([CLASSES.index(r[1]) for r in train_rows])
    y_val = np.array([CLASSES.index(r[1]) for r in val_rows])
    w, b = train(featurize(train_rows), y_train)

    q, scale = quantize(w)
    wq = q.astype(np.float32) * scale  # evaluate the shipped (quantized) model
    report = metrics(predict(featurize(val_rows), wq, b), y_val)
    print(f"validation accuracy {report['accuracy']}  top-3 "
          f"{report['top3_accuracy']}  macro-F1 {report['macro_f1']}")
    cross = None if args.quick else cross_split(rows)
    if cross:
        print(f"{cross['splits']} splits: accuracy {cross['accuracy_mean']}"
              f"±{cross['accuracy_std']}  top-3 {cross['top3_accuracy_mean']}"
              f"  macro-F1 {cross['macro_f1_mean']}")

    created = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    model = {
        "format": FORMAT,
        "schema_version": SCHEMA_VERSION,
        "preprocessing_version": PREPROCESSING_VERSION,
        "version": args.version,
        "created": created,
        "buckets": BUCKETS,
        "classes": CLASSES,
        "bias": [round(float(v), 6) for v in b],
        "scale": [float(v) for v in scale],
        "weights_b64": base64.b64encode(q.tobytes(order="C")).decode(),
        "metrics": {k: report[k] for k in ("accuracy", "top3_accuracy", "macro_f1")},
    }
    out = ROOT / "assets/ai/finora_classifier.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(model, ensure_ascii=False), encoding="utf-8")
    (ROOT / "tool/finora_ai/metrics.json").write_text(
        json.dumps({"version": args.version, "created": created,
                    "schema_version": SCHEMA_VERSION,
                    "preprocessing_version": PREPROCESSING_VERSION,
                    "train": len(train_rows), "validation": len(val_rows),
                    "validation_split": "held-out merchants (15% of names), "
                                        f"seed {SPLIT_SEEDS[0]}",
                    "data": "synthetic catalog set"
                            + (" + " + ", ".join(p.name for p in args.extra)
                               if args.extra else ""),
                    **({"cross_split": cross} if cross else {}),
                    **report}, ensure_ascii=False, indent=1),
        encoding="utf-8")

    # Parity fixtures: the Dart inference must give the same answers.
    fixtures = []
    for merchant, amount, kind in FIXTURES:
        t = TransactionInput(merchant, "", amount, kind, "card", date(2026, 5, 13))
        p = predict([vector(t, BUCKETS)], wq, b)[0]
        best = int(p.argmax())
        fixtures.append({"merchant": merchant, "amount_minor": amount,
                         "kind": kind, "account_type": "card",
                         "date": "2026-05-13", "class": CLASSES[best],
                         "p": round(float(p[best]), 4),
                         "preprocessing_version": PREPROCESSING_VERSION})
    (ROOT / "test/fixtures").mkdir(parents=True, exist_ok=True)
    (ROOT / "test/fixtures/finora_ai_parity.json").write_text(
        json.dumps(fixtures, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"wrote {out.relative_to(ROOT)} ({out.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
