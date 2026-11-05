# Android OCR changes in 1.5

## Reproduced gap

The prior `MAX_EDGE=2400` loop used power-of-two `inSampleSize` for every input.
A normal 1080×2401 screenshot therefore became approximately540×1200 before
OCR. This discarded small amount characters even though the original2.6MP image
was safe to decode. AUTO page segmentation also treats detached, right-aligned
bank-list amounts as separate layout blocks, and the previous text-only result
lost their relationship with merchant names.

The exact failing screenshot from the user's phone was not supplied during this
change. These findings reproduce concrete related failure mechanisms, not every
possible failure of the unavailable image.

## Native changes

- Decode within12MP/8000px bounds, preserving ordinary screenshot resolution;
  keep the original100MP source-dimension and20MiB compressed-file limits.
- Temporary EXIF-corrected pixels are grayscale, dark UI backgrounds are inverted
  after sampling63 points, and small inputs are smoothly enlarged up to1.6×.
  Prepared OCR pixels stay within roughly8MP/6400px. The stored attachment is
  never modified or uploaded.
- AUTO segmentation runs first. Empty/low-confidence/no-money output and
  portrait nonreceipt layouts receive one SPARSE_TEXT retry. Selection considers
  monetary candidates, useful text and confidence. Exactly one result is returned;
  outputs from two passes are never concatenated into duplicate operations.
- The selected ResultIterator is read at `RIL_TEXTLINE`. The iterator is deleted
  before the engine, temporary bitmaps are recycled, cancellation checks surround
  both passes and line extraction. Existing bounded worker/lifecycle code remains.

## Extended response

Existing `text` and `confidence` are retained. Optional `lines` (maximum2000):

```json
{
  "text": "ПЯТЁРОЧКА -1250,50 Р\nПродукты",
  "confidence": 0.85,
  "lines": [
    {
      "text": "ПЯТЁРОЧКА -1250,50 Р",
      "left": 0.1,
      "top": 0.16,
      "right": 0.94,
      "bottom": 0.18,
      "confidence": 0.91
    }
  ]
}
```

Coordinates are0..1 relative to the entire EXIF-corrected, axis-aligned image.
Scaling and grayscale/inversion preserve their relative positions. Sparse
segmentation can put a merchant and amount in different lines at the same Y;
Dart should group using geometry, not the iterator's reading order alone.
Confidence remains an uncalibrated OCR score, not correctness assurance.

## Verification and limits

`source tool/cloud_env.sh; cd android; ./gradlew :app:compileReleaseKotlin
--console=plain` passed (52s) after all native production changes. The downloaded
4.9.0 wrapper class signatures were checked with javap before using
`getResultIterator`, `getBoundingBox`, `confidence`, `next` and `delete`.

`python tool/check_native_ocr_v15.py` runs host Tesseract5.5.0 with the bundled
Russian/English models on generated dark and light1080×2560 bank-list fixtures.
Each contains five distinct merchants and right-aligned amounts:
−1250.50, −2875.80, −734.20, +89000.00, −360.00RUB. It compares the former half-size
AUTO input with the new preprocessing/pass choice and checks exact minor-unit
amounts plus normalized geometry. Old output merges the salary's currency into
`89 000,002`; the new output keeps the valid `89 000,00` amount separate.

The host check uses Pillow resizing/grayscale and TSV line grouping; it does
not execute Android Bitmap, EXIF, JNI or actual Kotlin pass selection. It verifies
real-model recognition of the input strategy and provides actual OCR wire-shaped
fixtures to the domain integration checks. It is not evidence of camera quality,
all bank templates or physical-phone recognition. The Android binary still needs
on-device rotated/mirrored/poor-light/cancel/low-memory and Share lifecycle checks.
Ruble glyphs are often read as Р/P or2, so domain parsing must retain uncertainty
and allow user correction instead of assuming every OCR character is exact.
