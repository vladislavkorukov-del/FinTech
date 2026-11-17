import 'dart:math' as math;

import '../models/ai_models.dart';
import '../services/ai_context.dart';

/// Longer patterns: categories rising or falling for months, how stable the
/// income is, everyday habits, unusual months and seasonality.
abstract final class FinancialPatternEngine {
  static Patterns compute(AiContext ctx) {
    final months = [for (var back = 6; back >= 1; back--) ctx.period(back)];
    // Monthly totals per category, oldest first.
    final series = <String, List<int>>{};
    for (var i = 0; i < months.length; i++) {
      final totals = ctx.byCategory(ctx.expensesIn(months[i].$1, months[i].$2));
      for (final t in totals.entries) {
        series.putIfAbsent(t.key, () => List.filled(months.length, 0))[i] =
            t.value;
      }
    }
    final trends = <CategoryTrend>[];
    for (final s in series.entries) {
      final last3 = s.value.sublist(s.value.length - 3);
      if (last3.any((v) => v == 0)) continue;
      final rising = last3[0] < last3[1] && last3[1] < last3[2];
      final falling = last3[0] > last3[1] && last3[1] > last3[2];
      // A steady move of at least 15% over the three months and 1 000 ₽.
      final change = (last3[2] - last3[0]).abs();
      if (change < 100000 || change < last3[0] * .15) continue;
      if (rising) trends.add(CategoryTrend(s.key, Trend.rising, last3));
      if (falling) trends.add(CategoryTrend(s.key, Trend.falling, last3));
    }
    return Patterns(
      trends: trends,
      habits: _habits(ctx),
      unusualMonths: _unusual(ctx),
      incomeStability: _incomeStability(ctx),
      seasonal: _seasonal(ctx),
    );
  }

  static Habits _habits(AiContext ctx) {
    final since = DateTime(ctx.now.year, ctx.now.month - 3, ctx.now.day);
    final recent = ctx.expenses.where((e) => !e.date.isBefore(since)).toList();
    if (recent.length < 10) return const Habits();
    final byDay = List<int>.filled(8, 0);
    for (final e in recent) {
      byDay[e.date.weekday] += e.amountMinor;
    }
    final total = recent.fold<int>(0, (a, e) => a + e.amountMinor);
    var best = 1;
    for (var d = 2; d <= 7; d++) {
      if (byDay[d] > byDay[best]) best = d;
    }
    final merchants = <String, (String, int)>{};
    for (final e in recent) {
      final key = AiContext.merchantKey(e.payee);
      if (key.isEmpty) continue;
      final old = merchants[key];
      merchants[key] = (e.payee.trim(), (old?.$2 ?? 0) + e.amountMinor);
    }
    final top = merchants.values.toList()..sort((a, b) => b.$2.compareTo(a.$2));
    return Habits(
      busiestWeekday: best,
      weekdayShare: total == 0 ? 0 : byDay[best] / total,
      averageExpense: (total / recent.length).round(),
      topMerchants: top.take(3).toList(),
    );
  }

  static List<UnusualMonth> _unusual(AiContext ctx) {
    final totals = <(DateTime, int)>[
      for (var back = 12; back >= 1; back--)
        (
          ctx.period(back).$1,
          ctx.sum(ctx.expensesIn(ctx.period(back).$1, ctx.period(back).$2)),
        ),
    ].where((m) => m.$2 > 0).toList();
    if (totals.length < 6) return const [];
    final values = [for (final t in totals) t.$2.toDouble()];
    final mean = values.reduce((a, b) => a + b) / values.length;
    final sd = math.sqrt(
      values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
          values.length,
    );
    if (sd == 0) return const [];
    return [
      for (final t in totals)
        if ((t.$2 - mean) / sd >= 2) UnusualMonth(t.$1, t.$2, mean.round()),
    ];
  }

  static IncomeStability? _incomeStability(AiContext ctx) {
    final values = <double>[
      for (var back = 6; back >= 1; back--)
        ctx
            .sum(ctx.incomesIn(ctx.period(back).$1, ctx.period(back).$2))
            .toDouble(),
    ].where((v) => v > 0).toList();
    if (values.length < 3) return null;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final sd = math.sqrt(
      values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
          values.length,
    );
    final cv = sd / mean;
    return cv < .15
        ? IncomeStability.stable
        : cv < .4
        ? IncomeStability.moderate
        : IncomeStability.volatile;
  }

  /// The same period a year ago against the year's monthly average, per
  /// category — repeating seasonal spending (needs a year of history).
  static List<CategoryChange> _seasonal(AiContext ctx) {
    final yearAgo = ctx.period(12);
    if (ctx.expensesIn(yearAgo.$1, yearAgo.$2).isEmpty) return const [];
    final then = ctx.byCategory(ctx.expensesIn(yearAgo.$1, yearAgo.$2));
    final avg = <String, int>{};
    for (var back = 1; back <= 12; back++) {
      final t = ctx.byCategory(
        ctx.expensesIn(ctx.period(back).$1, ctx.period(back).$2),
      );
      for (final e in t.entries) {
        avg[e.key] = (avg[e.key] ?? 0) + e.value;
      }
    }
    final out = <CategoryChange>[];
    for (final e in then.entries) {
      final mean = (avg[e.key] ?? 0) ~/ 12;
      if (mean > 0 && e.value > mean * 1.5 && e.value - mean >= 200000) {
        out.add(
          CategoryChange(categoryId: e.key, current: e.value, previous: mean),
        );
      }
    }
    return out;
  }
}
