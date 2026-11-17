import 'models.dart';
import 'payee_summary.dart';

/// Possible duplicates of an operation about to be saved: the same kind,
/// sum, currency and account within a day, at the same place (or, without
/// a place, in the same category). Nothing is removed — the person decides.
abstract final class DuplicateDetector {
  static List<FinanceEntry> find(FinanceEntry entry, List<FinanceEntry> all) {
    final key = PayeeSummary.key(entry.payee);
    return [
      for (final e in all)
        if (e.id != entry.id &&
            e.status != 'cancelled' &&
            e.kind == entry.kind &&
            e.amountMinor == entry.amountMinor &&
            e.currency == entry.currency &&
            e.accountId == entry.accountId &&
            e.date.difference(entry.date).inHours.abs() <= 24 &&
            (key.isNotEmpty
                ? PayeeSummary.key(e.payee) == key
                : e.payee.trim().isEmpty && e.categoryId == entry.categoryId))
          e,
    ];
  }
}
