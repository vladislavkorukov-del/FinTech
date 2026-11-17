import 'dart:math' as math;

import '../../../domain/models.dart';
import '../models/ai_models.dart';
import '../services/ai_context.dart';

/// Unusually large expenses in the current period. An expense is compared
/// with the same category's history before this period (median and a robust
/// spread, MAD); it needs at least [minHistory] past expenses, so nothing is
/// called «unusual» without a real norm to compare with.
abstract final class AnomalyDetector {
  static const minHistory = 5;

  /// Smallest amount worth flagging (1 000 ₽).
  static const floorMinor = 100000;

  static List<Anomaly> detect(AiContext ctx) {
    final history = ctx.expenses
        .where((e) => e.date.isBefore(ctx.periodStart))
        .where(
          (e) => !e.date.isBefore(
            DateTime(ctx.periodStart.year, ctx.periodStart.month - 6),
          ),
        )
        .toList();
    final current = ctx.expensesIn(ctx.periodStart, ctx.periodEnd);
    final byCategory = <String, List<int>>{};
    for (final e in history) {
      byCategory.putIfAbsent(e.categoryId ?? '', () => []).add(e.amountMinor);
    }
    final seenMerchants = {
      for (final e in history) AiContext.merchantKey(e.payee),
    };
    final out = <Anomaly>[];
    for (final e in current) {
      if (e.amountMinor < floorMinor) continue;
      final past = byCategory[e.categoryId ?? ''];
      if (past == null || past.length < minHistory) continue;
      final mid = median(past);
      final mad = median([for (final a in past) (a - mid).abs()]) * 1.4826;
      final limit = math.max(mid * 3, mid + 4 * mad);
      if (e.amountMinor <= limit) continue;
      final key = AiContext.merchantKey(e.payee);
      out.add(
        Anomaly(
          entry: e,
          typical: mid.round(),
          ratio: mid == 0 ? 0 : e.amountMinor / mid,
          firstAtMerchant: key.isNotEmpty && !seenMerchants.contains(key),
        ),
      );
    }
    out.sort((a, b) => b.entry.amountMinor.compareTo(a.entry.amountMinor));
    return out;
  }

  /// Big one-off purchases this period: anomalies at a merchant never seen
  /// before (likely unplanned).
  static List<Anomaly> unplanned(AiContext ctx) =>
      detect(ctx).where((a) => a.firstAtMerchant).toList();

  /// Whether [e] would be unusual for its category (used by forecasts to
  /// keep one-off purchases out of the daily pace).
  static bool isOneOff(FinanceEntry e, List<Anomaly> anomalies) =>
      anomalies.any((a) => a.entry.id == e.id);
}
