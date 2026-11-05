import 'models.dart';

const _unchanged = Object();

/// OCR suggestions only. A user must review this draft before any ledger write.
/// Amounts use the same integer minor units as the financial domain.
class ScanDraft {
  const ScanDraft({
    required this.rawText,
    this.amountMinor,
    this.currency,
    this.payee,
    this.date,
    this.kind,
    this.categoryId,
    this.comment = '',
    this.warnings = const [],
  });

  final int? amountMinor;
  final String? currency;
  final String? payee;
  final DateTime? date;
  final EntryKind? kind;
  final String? categoryId;
  final String comment;
  final List<String> warnings;
  final String rawText;

  ScanDraft copyWith({
    Object? amountMinor = _unchanged,
    Object? currency = _unchanged,
    Object? payee = _unchanged,
    Object? date = _unchanged,
    Object? kind = _unchanged,
    Object? categoryId = _unchanged,
    String? comment,
    List<String>? warnings,
    String? rawText,
  }) => ScanDraft(
    amountMinor: identical(amountMinor, _unchanged)
        ? this.amountMinor
        : amountMinor as int?,
    currency: identical(currency, _unchanged)
        ? this.currency
        : currency as String?,
    payee: identical(payee, _unchanged) ? this.payee : payee as String?,
    date: identical(date, _unchanged) ? this.date : date as DateTime?,
    kind: identical(kind, _unchanged) ? this.kind : kind as EntryKind?,
    categoryId: identical(categoryId, _unchanged)
        ? this.categoryId
        : categoryId as String?,
    comment: comment ?? this.comment,
    warnings: warnings == null ? this.warnings : List.unmodifiable(warnings),
    rawText: rawText ?? this.rawText,
  );
}
