Synthetic Russian OCR fixtures drawn with DejaVu Sans for engine testing. These are generated test inputs, not screenshots from a real bank, shop, account or person. Model files are bundled under assets/ocr.

`v15-dark-wire.json` and `v15-light-wire.json` record actual host Tesseract output
from the synthetic five-row bank page produced by `tool/check_native_ocr_v15.py`.
They preserve OCR mistakes (including a ruble glyph read as a detached `2`) and
normalized TSV line geometry without manual correction of text. Parser regression
checks use these records; they are not photographs or financial data from a user.

`v16-receipts.json` (Finance 1.6) records actual host Tesseract 5 output with the
bundled `rus+eng` models for **synthetic** till-receipt photos: a generated
receipt (DejaVu Sans Mono) with rotation, blur, a shadow gradient, noise and
JPEG compression. `v16-*` entries use the 1.6 pipeline (illumination
flattening + enlarged second pass over the total band, emulated on the host);
`v15-pipeline-*` uses the 1.5 preprocessing without the second pass. `text`,
`lines` and `focus` are kept exactly as recognized (`v163-*`: the 1.6.3
focus pass — whole-page single-block reading plus binarized re-reads of the
total bands), including OCR mistakes.
`printedTotalMinor` is the total drawn on the image; `expectedMinor` is what
the parser must return (null where the text is unreadable). These are not
photographs of real receipts.
