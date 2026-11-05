#!/usr/bin/env python3
"""Host reproduction of native preprocessing/segmentation with synthetic UI.

No real bank image or user data. This exercises the bundled OCR models on the
host; it does not execute Android Bitmap, EXIF, JNI or the Kotlin implementation.
Requires Tesseract CLI, Pillow and DejaVu Sans. Generated inputs and actual OCR
output stay in a temporary directory, printed when the assertions pass.
"""

import csv
import io
import json
import re
import statistics
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
MONEY = re.compile(
    r"(?<![\d/.])(?:[+-]\s*)?\d(?:[ \u00a0\u202f]?\d)*[,.]\d{2}(?![\d/.])"
    r"|(?<!\d)\d[\d ]*[₽$€]"
)
EXPECTED = [-125050, -287580, -73420, 8900000, -36000]


def fixture(path, dark=True):
    background = "#0e1117" if dark else "#f6f7f9"
    foreground = "#f0f3f7" if dark else "#141921"
    hint = "#a7b1c0" if dark else "#5e6876"
    image = Image.new("RGB", (1080, 2560), background)
    drawing = ImageDraw.Draw(image)

    def text(x, y, value, size=26, color=foreground, bold=False):
        font = ImageFont.truetype(BOLD if bold else FONT, size)
        drawing.text((x, y), value, fill=color, font=font)

    text(80, 100, "История операций", 38, bold=True)
    text(80, 200, "5 ноября 2026", 24, color=hint)
    rows = [
        ("ПЯТЁРОЧКА", "- 1 250,50 ₽", "Продукты"),
        ("АЗС ЛУКОЙЛ", "- 2 875,80 ₽", "Топливо"),
        ("Аптека Ригла", "- 734,20 ₽", "Здоровье"),
        ("Зарплата", "+ 89 000,00 ₽", "Пополнение"),
        ("Кофейня", "- 360,00 ₽", "Рестораны"),
    ]
    for index, (merchant, amount, category) in enumerate(rows):
        y = 400 + index * 340
        text(115, y, merchant, 29, bold=True)
        # Detached, right-aligned amounts exercise the bank-list layout seam.
        box = drawing.textbbox(
            (0, 0), amount, font=ImageFont.truetype(FONT, 29)
        )
        text(1010 - (box[2] - box[0]), y, amount, 29)
        text(115, y + 65, category, 24, color=hint)
        text(115, y + 115, f"12:{10 + index:02d}", 22, color=hint)
        drawing.line(
            (80, y + 260, 1010, y + 260),
            fill="#252c38" if dark else "#dee2e8",
            width=1,
        )
    image.save(path)
    return image


def recognized(path, segmentation):
    result = subprocess.run(
        [
            "tesseract", str(path), "stdout",
            "--tessdata-dir", str(ROOT / "assets/ocr/tessdata"),
            "-l", "rus+eng", "--psm", str(segmentation), "--dpi", "300",
            "-c", "tessedit_create_tsv=1", "-c", "tessedit_create_txt=0",
        ],
        text=True,
        capture_output=True,
        check=True,
    )
    rows = list(csv.DictReader(io.StringIO(result.stdout), delimiter="\t"))
    words = [
        row for row in rows
        if row["level"] == "5" and row["text"].strip() and float(row["conf"]) >= 0
    ]
    groups = {}
    for word in words:
        key = tuple(word[k] for k in ["page_num", "block_num", "par_num", "line_num"])
        groups.setdefault(key, []).append(word)
    with Image.open(path) as image:
        width, height = image.size
    lines = []
    for group in groups.values():
        lines.append({
            "text": " ".join(word["text"] for word in group),
            "left": min(int(word["left"]) for word in group) / width,
            "top": min(int(word["top"]) for word in group) / height,
            "right": max(int(word["left"]) + int(word["width"]) for word in group) / width,
            "bottom": max(int(word["top"]) + int(word["height"]) for word in group) / height,
            "confidence": statistics.mean(float(word["conf"]) for word in group) / 100,
        })
    return {
        "words": words,
        "text": "\n".join(line["text"] for line in lines),
        "lines": lines,
        "confidence": statistics.mean(float(word["conf"]) for word in words) / 100 if words else 0,
    }


def choose(first, sparse):
    """Mirror Kotlin's bounded pass choice; confidence aggregation is host TSV."""
    def useful(result):
        return sum(character.isalnum() for character in result["text"])

    def count(result):
        return len(MONEY.findall(result["text"]))

    if useful(sparse) == 0:
        return first
    if useful(first) == 0:
        return sparse
    if (
        count(sparse) > count(first)
        and sparse["confidence"] >= first["confidence"] - .12
        and useful(sparse) >= useful(first) * .6
    ):
        return sparse
    if count(sparse) >= count(first) and sparse["confidence"] > first["confidence"] + .06:
        return sparse
    return first


def amounts(text):
    result = []
    for match in MONEY.finditer(text):
        value = re.sub(r"[ \u00a0\u202f₽$€]", "", match.group())
        if "," in value or "." in value:
            whole, fraction = re.split(r"[,.]", value)
            sign = -1 if whole.startswith("-") else 1
            result.append(sign * (abs(int(whole)) * 100 + int(fraction)))
    return result


def main():
    folder = Path(tempfile.mkdtemp(prefix="finance-native-v15-"))
    results = {}
    for dark in (True, False):
        label = "dark" if dark else "light"
        original = fixture(folder / f"{label}.png", dark)
        # v1.4's MAX_EDGE2400 used inSampleSize2 for this 1080x2560 input.
        baseline_path = folder / f"{label}-old.png"
        original.resize((540, 1280), Image.Resampling.LANCZOS).save(baseline_path)
        old = recognized(baseline_path, 3)

        gray = original.convert("L", (.213, .715, .072, 0))
        if dark:
            gray = ImageOps.invert(gray)
        prepared = gray.resize(
            (1400, round(2560 * 1400 / 1080)), Image.Resampling.BILINEAR
        )
        prepared_path = folder / f"{label}-prepared.png"
        prepared.save(prepared_path)
        automatic = recognized(prepared_path, 3)
        sparse = recognized(prepared_path, 11)
        chosen = choose(automatic, sparse)

        assert amounts(chosen["text"]) == EXPECTED, (label, chosen["text"])
        # Baseline merges the salary's currency into the fraction: 89 000,002.
        assert amounts(old["text"]) != EXPECTED, (label, old["text"])
        for merchant in ["ПЯТЁРОЧКА", "ЛУКОЙЛ", "Ригла", "Зарплата", "Кофейня"]:
            assert merchant.casefold() in chosen["text"].casefold(), (label, merchant)
        monetary_lines = [line for line in chosen["lines"] if MONEY.search(line["text"])]
        assert len(monetary_lines) == 5, (label, monetary_lines)
        assert len({round(line["top"], 2) for line in monetary_lines}) == 5
        for line in chosen["lines"]:
            assert 0 <= line["left"] < line["right"] <= 1
            assert 0 <= line["top"] < line["bottom"] <= 1

        wire = {key: chosen[key] for key in ["text", "confidence", "lines"]}
        (folder / f"{label}-wire.json").write_text(
            json.dumps(wire, ensure_ascii=False, indent=2)
        )
        results[label] = {
            "oldAmounts": amounts(old["text"]),
            "newAmounts": amounts(chosen["text"]),
            "oldText": old["text"],
            "newText": chosen["text"],
            "monetaryRows": len(monetary_lines),
            "chosen": "sparse" if chosen is sparse else "auto",
            "autoConfidence": automatic["confidence"],
            "sparseConfidence": sparse["confidence"],
        }
    (folder / "result.json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2)
    )
    print(json.dumps({"fixtures": str(folder), "passed": True, "results": results},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
