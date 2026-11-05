Synthetic Russian OCR fixtures drawn with DejaVu Sans for engine testing. These are generated test inputs, not screenshots from a real bank, shop, account or person. Model files are bundled under assets/ocr.

`v15-dark-wire.json` and `v15-light-wire.json` record actual host Tesseract output
from the synthetic five-row bank page produced by `tool/check_native_ocr_v15.py`.
They preserve OCR mistakes (including a ruble glyph read as a detached `2`) and
normalized TSV line geometry without manual correction of text. Parser regression
checks use these records; they are not photographs or financial data from a user.
