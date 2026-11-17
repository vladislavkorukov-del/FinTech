import 'dart:math' as math;

import '../../../domain/finance_engine.dart';
import '../../../domain/models.dart';
import '../detectors/anomaly_detector.dart';
import '../forecasting/cashflow_engine.dart';
import '../models/ai_models.dart';
import '../services/ai_context.dart';

/// Chance of going over each budget by the end of the period: spent so
/// far (the app's own [FinanceEngine.budgetSpent]) plus the category's
/// everyday pace and its regular payments still due. The probability comes
/// from how much the daily spending in that category varies.
abstract final class BudgetRiskEngine {
  static List<BudgetRisk> compute(AiContext ctx, {List<Anomaly>? anomalies}) {
    final a = anomalies ?? AnomalyDetector.detect(ctx);
    final out = <BudgetRisk>[];
    if (ctx.daysPassed < 3) return out;
    final dueByCategory = <String?, int>{};
    for (final (r, _) in CashflowEngine.upcoming(ctx, EntryKind.expense)) {
      dueByCategory[r.categoryId] =
          (dueByCategory[r.categoryId] ?? 0) + r.amountMinor;
    }
    for (final b in ctx.data.budgets) {
      if (b.currency != ctx.currency || b.limitMinor <= 0) continue;
      final spent = FinanceEngine.budgetSpent(
        b,
        ctx.data.entries,
        ctx.periodStart,
        ctx.periodEnd,
      );
      final list = ctx
          .expensesIn(ctx.periodStart, ctx.periodEnd)
          .where((e) => b.categoryId == null || e.categoryId == b.categoryId)
          .where((e) => !AnomalyDetector.isOneOff(e, a))
          .where((e) => !CashflowEngine.isRegular(ctx, e))
          .toList();
      final daily = List<double>.filled(ctx.daysPassed, 0);
      for (final e in list) {
        final d = e.date.difference(ctx.periodStart).inDays;
        if (d >= 0 && d < daily.length) daily[d] += e.amountMinor;
      }
      final mean = daily.reduce((x, y) => x + y) / daily.length;
      final variance =
          daily.map((v) => (v - mean) * (v - mean)).reduce((x, y) => x + y) /
          daily.length;
      final due = b.categoryId == null
          ? dueByCategory.values.fold(0, (x, y) => x + y)
          : dueByCategory[b.categoryId] ?? 0;
      final projected = spent + (mean * ctx.daysLeft).round() + due;
      // Normal approximation of the remaining spending.
      final sd = math.sqrt(variance * ctx.daysLeft);
      final gap = b.limitMinor - projected;
      final probability = spent >= b.limitMinor
          ? 1.0
          : sd == 0
          ? (gap < 0 ? 1.0 : 0.0)
          : _phi(-gap / sd);
      out.add(
        BudgetRisk(
          budget: b,
          spent: spent,
          projected: projected,
          probability: probability,
          due: due,
          daysLeft: ctx.daysLeft,
        ),
      );
    }
    out.sort((x, y) => y.probability.compareTo(x.probability));
    return out;
  }

  /// Standard normal CDF.
  static double _phi(double x) => .5 * (1 + _erf(x / math.sqrt2));

  static double _erf(double x) {
    // Abramowitz–Stegun 7.1.26.
    final t = 1 / (1 + .3275911 * x.abs());
    final y =
        1 -
        (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t -
                        .284496736) *
                    t +
                .254829592) *
            t *
            math.exp(-x * x);
    return x >= 0 ? y : -y;
  }
}
