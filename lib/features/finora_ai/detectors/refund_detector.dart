import '../../../domain/models.dart';
import '../classification/merchant_intelligence.dart';

/// Money that came back is not income: a refund is an incoming operation
/// called so («Возврат», «refund», «вернули»), or one from a place where
/// the same or a larger sum was spent shortly before. It is matched to that
/// expense when one exists.
abstract final class RefundDetector {
  static final _words = RegExp(
    r'возврат|refund|вернули|отмена покупки|chargeback|cashback|кэшбэк|кешбек',
    caseSensitive: false,
  );

  /// How far back an expense can be refunded.
  static const window = Duration(days: 60);

  /// The expense [income] refunds, if any (null also when it is a refund
  /// by name only).
  static FinanceEntry? matchOf(FinanceEntry income, List<FinanceEntry> all) {
    final key = MerchantIntelligence.canonicalKey(income.payee);
    if (key.isEmpty) return null;
    FinanceEntry? best;
    for (final e in all) {
      if (e.kind != EntryKind.expense ||
          e.currency != income.currency ||
          e.amountMinor < income.amountMinor ||
          e.date.isAfter(income.date) ||
          income.date.difference(e.date) > window) {
        continue;
      }
      if (MerchantIntelligence.canonicalKey(e.payee) != key) continue;
      if (best == null || e.date.isAfter(best.date)) best = e;
    }
    return best;
  }

  static bool isRefund(FinanceEntry e, List<FinanceEntry> all) {
    if (e.kind != EntryKind.income) return false;
    if (_words.hasMatch('${e.payee} ${e.note}')) return true;
    return matchOf(e, all) != null;
  }
}
