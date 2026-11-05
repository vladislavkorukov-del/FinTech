import 'scan_draft.dart';

/// One OCR text line in the EXIF-corrected image; coordinates are normalized.
class RecognizedLine {
  const RecognizedLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.confidence,
  });
  final String text;
  final double left, top, right, bottom, confidence;
}

/// Suggestions awaiting explicit user review, never financial writes.
class ScanDocument {
  const ScanDocument({
    required this.drafts,
    this.warnings = const [],
    this.isStatement = false,
  });
  final List<ScanDraft> drafts;
  final List<String> warnings;
  final bool isStatement;
}
