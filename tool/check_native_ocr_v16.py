#!/usr/bin/env python3
"""Host check of the 1.6.1 native OCR additions with synthetic images only.

Mirrors ReceiptOcrEngine.kt on the host (Tesseract CLI + bundled models):
1. illumination flattening must keep the 1.5 bank-page result unchanged
   (dark and light, five operations);
2. (1.6.2) on a synthetic dark bank screen with thin amount digits the
   per-row amount re-read (binarized, digits only) returns every amount.
Does not execute Android Bitmap/JNI code. Requires Tesseract, Pillow, NumPy.
"""
import re
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps

import check_native_ocr_v15 as v15

MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
MONO_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"


def flatten(gray):
    """Same as flattenIllumination(): divide by smoothed block maxima."""
    a = np.asarray(gray, dtype=np.float32)
    h, w = a.shape
    b = max(8, min(w, h) // 40)
    hb, wb = (h + b - 1) // b, (w + b - 1) // b
    pad = np.pad(a, ((0, hb * b - h), (0, wb * b - w)), mode="edge")
    maxima = pad.reshape(hb, b, wb, b).max(axis=(1, 3))
    p = np.pad(maxima, 1, mode="edge")
    smooth = sum(p[i:i + hb, j:j + wb] for i in range(3) for j in range(3)) / 9
    fy = np.clip((np.arange(h) + .5) / b - .5, 0, hb - 1)
    fx = np.clip((np.arange(w) + .5) / b - .5, 0, wb - 1)
    y0, x0 = fy.astype(int), fx.astype(int)
    y1, x1 = np.minimum(y0 + 1, hb - 1), np.minimum(x0 + 1, wb - 1)
    ty, tx = (fy - y0)[:, None], (fx - x0)[None, :]
    top = smooth[y0][:, x0] * (1 - tx) + smooth[y0][:, x1] * tx
    bottom = smooth[y1][:, x0] * (1 - tx) + smooth[y1][:, x1] * tx
    background = np.maximum(top * (1 - ty) + bottom * ty, 1)
    return Image.fromarray(np.clip(np.rint(a * 255 / background), 0, 255).astype(np.uint8))


def prepared(path):
    gray = ImageOps.grayscale(Image.open(path))
    scale = min(1.6, 1400 / gray.width) if gray.width < 1400 else 1.0
    return gray.resize((round(gray.width * scale), round(gray.height * scale)), Image.BILINEAR)


ROBOTO = "/opt/tools/flutter/bin/cache/artifacts/material_fonts"
THIN_ROWS = [("Анна Сергеевна П.", "-10 000 ₽"), ("Пётр Иванович Л.", "+10 000 ₽"),
             ("AVITO", "-2 597 ₽"), ("Ольга Викторовна Д.", "+3 600 ₽"),
             ("Пятёрочка", "-549,45 ₽"), ("Whoosh", "-82,90 ₽"), ("Whoosh", "-26,97 ₽"),
             ("Магнит", "-249,68 ₽")]


def thin_bank_screen(path, fonts):
    regular = ImageFont.truetype(f"{fonts}/Roboto-Regular.ttf", 46)
    light = ImageFont.truetype(f"{fonts}/Roboto-Light.ttf", 46)
    small = ImageFont.truetype(f"{fonts}/Roboto-Regular.ttf", 34)
    image = Image.new("RGB", (1080, 1720), "#1d2024")
    draw = ImageDraw.Draw(image)
    draw.text((48, 50), "Вчера", font=regular, fill="#9aa0a6")
    y = 150
    for name, amount in THIN_ROWS:
        draw.rounded_rectangle((46, y, 170, y + 124), radius=34, fill="#6b5ce7")
        draw.text((204, y + 6), name, font=regular, fill="#ffffff")
        draw.text((204, y + 76), "Категория", font=small, fill="#9aa0a6")
        width = light.getbbox(amount)[2]
        draw.text((1034 - width, y + 6), amount, font=light,
                  fill="#3ddc84" if amount.startswith("+") else "#ffffff")
        y += 191
    image.save(path)


def amount_rereads(gray, lines, folder):
    width, height = gray.size
    found = []
    for line in lines:
        if line["left"] >= .5 or line["right"] >= .85 or not re.search(r"[A-Za-zА-Яа-я]", line["text"]):
            continue
        h = (line["bottom"] - line["top"]) * height
        y0, y1 = max(0, int(line["top"] * height - .4 * h)), min(height, int(line["bottom"] * height + .4 * h))
        x0 = int(width * max(.45, line["right"] + .015))
        if width - x0 < width * .08:
            continue
        scale = max(1.2, min(2.5, 56 / h))
        crop = gray.crop((x0, y0, width, y1))
        crop = flatten(crop.resize((int(crop.width * scale), int(crop.height * scale)), Image.BICUBIC))
        crop = crop.point(lambda v: 255 if v > 170 else 0)
        path = folder / "amount.png"
        crop.save(path)
        text = subprocess.run(["tesseract", str(path), "stdout", "--tessdata-dir",
                               str(v15.ROOT / "assets/ocr/tessdata"), "-l", "rus+eng", "--psm", "7",
                               "--dpi", "300", "-c", "tessedit_char_whitelist=0123456789+-,.₽РP "],
                              capture_output=True, text=True, check=True).stdout.strip()
        if re.search(r"\d", text):
            found.append(text)
    return found


def main():
    folder = Path(tempfile.mkdtemp(prefix="finance-native-v16-"))
    for dark in (True, False):
        original = v15.fixture(folder / "bank.png", dark)
        gray = original.convert("L", (.213, .715, .072, 0))
        if dark:
            gray = ImageOps.invert(gray)
        gray = flatten(gray.resize((1400, round(2560 * 1400 / 1080)), Image.BILINEAR))
        path = folder / "bank-flat.png"
        gray.save(path)
        chosen = v15.choose(v15.recognized(path, 3), v15.recognized(path, 11))
        assert v15.amounts(chosen["text"]) == v15.EXPECTED, (dark, chosen["text"])
    thin = "unchecked (Roboto from the Flutter SDK not found)"
    if Path(ROBOTO).is_dir():
        screen = folder / "thin.png"
        thin_bank_screen(screen, ROBOTO)
        gray = flatten(ImageOps.invert(prepared(screen)))
        gray.save(folder / "thin-prepared.png")
        lines = v15.recognized(folder / "thin-prepared.png", 3)["lines"]
        rereads = [re.sub(r"\s+", "", t).rstrip("₽РP2") for t in amount_rereads(gray, lines, folder)]
        wanted = [re.sub(r"\s+", "", a).rstrip("₽") for _, a in THIN_ROWS]
        assert rereads == wanted, (rereads, wanted)
        thin = f"{len(rereads)}/{len(THIN_ROWS)} amounts re-read exactly"
    print({"bankUnchanged": True, "thinBankScreen": thin, "fixtures": str(folder)})


if __name__ == "__main__":
    main()
