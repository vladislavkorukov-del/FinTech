import 'dart:math' as math;

import '../../../domain/models.dart';
import '../models/ai_models.dart';
import '../services/ai_context.dart';

/// Unusually large expenses in the current period, judged by this person's
/// own behaviour, never by a fixed threshold. An expense is compared with
/// the same place's past payments when there are enough of them (a big
/// grocery run at the usual supermarket is not «unusual» because cafés are
/// cheap), otherwise with its category's history (median and a robust
/// spread, MAD). A norm needs at least [minHistory] past expenses
/// ([minMerchantHistory] for one place).
abstract final class AnomalyDetector {
  static const minHistory = 5;
  static const minMerchantHistory = 4;

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
    final byMerchant = <String, List<int>>{};
    for (final e in history) {
      byCategory.putIfAbsent(e.categoryId ?? '', () => []).add(e.amountMinor);
      final key = AiContext.merchantKey(e.payee);
      if (key.isNotEmpty) {
        byMerchant.putIfAbsent(key, () => []).add(e.amountMinor);
      }
    }
    final seenMerchants = {
      for (final e in history) AiContext.merchantKey(e.payee),
    };
    final out = <Anomaly>[];
    for (final e in current) {
      if (e.amountMinor < floorMinor) continue;
      final key = AiContext.merchantKey(e.payee);
      final atPlace = byMerchant[key];
      final byPlace = atPlace != null && atPlace.length >= minMerchantHistory;
      final past = byPlace ? atPlace : byCategory[e.categoryId ?? ''];
      if (past == null || past.length < minHistory && !byPlace) continue;
      final mid = median(past);
      final mad = median([for (final a in past) (a - mid).abs()]) * 1.4826;
      final limit = byPlace
          ? math.max(mid * 2.5, mid + 4 * mad)
          : math.max(mid * 3, mid + 4 * mad);
      if (e.amountMinor <= limit) continue;
      out.add(
        Anomaly(
          entry: e,
          typical: mid.round(),
          ratio: mid == 0 ? 0 : e.amountMinor / mid,
          firstAtMerchant: key.isNotEmpty && !seenMerchants.contains(key),
          basis: byPlace ? AnomalyBasis.merchant : AnomalyBasis.category,
          history: past.length,
        ),
      );
    }
    out.sort((a, b) => b.entry.amountMinor.compareTo(a.entry.amountMinor));
    return out;
  }

  /// Many more operations than usual by this day of the period: the count
  /// so far against the median count of the last full periods at the same
  /// share of the period. Needs three periods of history.
  static FrequencyAnomaly? frequency(AiContext ctx) {
    final periods = ctx.fullPeriodsWithData.take(6).toList();
    if (periods.length < 3 || ctx.daysPassed < 5) return null;
    final share = ctx.daysPassed / ctx.periodDays;
    final counts = <int>[];
    for (final back in periods) {
      final (s, e) = ctx.period(back);
      counts.add(ctx.expensesIn(s, e).length);
    }
    final typical = (median(counts) * share).round();
    final count = ctx.expensesIn(ctx.periodStart, ctx.periodEnd).length;
    if (typical < 5 || count < typical * 1.6 || count - typical < 8) {
      return null;
    }
    return FrequencyAnomaly(count: count, typical: typical);
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
