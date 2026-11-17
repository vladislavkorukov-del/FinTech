import '../models/ai_models.dart';
import '../services/ai_context.dart';

/// Compares spending of the current period with the previous one, fairly:
/// the same number of days from the start of each period. Finds the
/// categories that drove the change.
abstract final class MonthComparisonEngine {
  /// A category change must be at least this big to be a «driver» (500 ₽).
  static const minDriverMinor = 50000;

  static MonthComparison compute(AiContext ctx) {
    final days = ctx.daysPassed.clamp(1, ctx.periodDays);
    final (ps, _) = ctx.period(1);
    final current = ctx.expensesIn(ctx.periodStart, ctx.periodEnd);
    final previous = ctx.expensesIn(ps, ps.add(Duration(days: days)));
    final cur = ctx.byCategory(current), prev = ctx.byCategory(previous);
    final changes = [
      for (final id in {...cur.keys, ...prev.keys})
        CategoryChange(
          categoryId: id,
          current: cur[id] ?? 0,
          previous: prev[id] ?? 0,
        ),
    ];
    final up = changes.where((c) => c.difference >= minDriverMinor).toList()
      ..sort((a, b) => b.difference.compareTo(a.difference));
    final down = changes.where((c) => c.difference <= -minDriverMinor).toList()
      ..sort((a, b) => a.difference.compareTo(b.difference));
    final enough = previous.length >= 3 && current.isNotEmpty;
    return MonthComparison(
      current: ctx.sum(current),
      previous: ctx.sum(previous),
      comparableDays: days,
      drivers: up.take(3).toList(),
      decreases: down.take(3).toList(),
      insufficient: enough
          ? null
          : Insufficient(
              previous.isEmpty
                  ? InsufficientReason.noPreviousPeriod
                  : InsufficientReason.tooFewEntries,
            ),
    );
  }

  /// Categories where spending this period (so far) is notably above their
  /// own usual level for the same number of days (median of the last full
  /// periods, scaled): «на продукты на 5 200 ₽ больше, чем обычно».
  static List<CategoryChange> aboveUsual(AiContext ctx) {
    final periods = ctx.fullPeriodsWithData.take(3).toList();
    if (periods.length < 2) return const [];
    final share = ctx.daysPassed / ctx.periodDays;
    final cur = ctx.byCategory(ctx.expensesIn(ctx.periodStart, ctx.periodEnd));
    final usual = <String, List<int>>{};
    for (final back in periods) {
      final (s, e) = ctx.period(back);
      final totals = ctx.byCategory(ctx.expensesIn(s, e));
      for (final id in {...totals.keys, ...cur.keys}) {
        usual.putIfAbsent(id, () => []).add(totals[id] ?? 0);
      }
    }
    final out = <CategoryChange>[];
    for (final u in usual.entries) {
      final norm = (median(u.value) * share).round();
      final now = cur[u.key] ?? 0;
      if (norm > 0 && now - norm >= minDriverMinor * 2 && now > norm * 1.25) {
        out.add(
          CategoryChange(categoryId: u.key, current: now, previous: norm),
        );
      }
    }
    out.sort((a, b) => b.difference.compareTo(a.difference));
    return out;
  }
}
