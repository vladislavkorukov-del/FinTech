import '../models/ai_models.dart';
import '../services/ai_context.dart';

/// Compares spending of the current period with the previous one, fairly:
/// the same number of days from the start of each period. Finds the
/// categories that drove the change. [comparePeriods] does the same for a
/// day, week, month, quarter, year or a custom range, with income and cash
/// flow too.
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

  /// The current [unit] (up to the end of today) against the same stretch
  /// of the previous one; or [start]–[end] (end exclusive) against the range
  /// of the same length right before it.
  static PeriodComparison comparePeriods(
    AiContext ctx, {
    PeriodUnit? unit,
    DateTime? start,
    DateTime? end,
  }) {
    assert(unit != null || (start != null && end != null));
    final today = DateTime(ctx.now.year, ctx.now.month, ctx.now.day);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    late DateTime curStart, curEnd, prevStart, prevEnd;
    if (unit == null) {
      curStart = start!;
      curEnd = end!;
      final days = curEnd.difference(curStart).inDays;
      prevStart = DateTime(curStart.year, curStart.month, curStart.day - days);
      prevEnd = curStart;
    } else {
      final (s, fullPrevStart, fullPrevEnd) = _bounds(ctx, unit, today);
      curStart = s;
      curEnd = tomorrow;
      prevStart = fullPrevStart;
      // The same number of days into the previous period, never past it.
      final elapsed = curEnd.difference(curStart).inDays;
      final fairEnd = DateTime(
        prevStart.year,
        prevStart.month,
        prevStart.day + elapsed,
      );
      prevEnd = fairEnd.isBefore(fullPrevEnd) ? fairEnd : fullPrevEnd;
    }
    final curExp = ctx.expensesIn(curStart, curEnd);
    final prevExp = ctx.expensesIn(prevStart, prevEnd);
    final curInc = ctx.incomesIn(curStart, curEnd);
    final prevInc = ctx.incomesIn(prevStart, prevEnd);
    final cur = ctx.byCategory(curExp), prev = ctx.byCategory(prevExp);
    final small = unit == PeriodUnit.day || unit == PeriodUnit.week;
    final threshold = small ? minDriverMinor ~/ 2.5 : minDriverMinor;
    final deltas = [
      for (final id in {...cur.keys, ...prev.keys})
        CategoryDelta(id, cur[id] ?? 0, prev[id] ?? 0),
    ];
    final up = deltas.where((d) => d.difference >= threshold).toList()
      ..sort((a, b) => b.difference.compareTo(a.difference));
    final down = deltas.where((d) => d.difference <= -threshold).toList()
      ..sort((a, b) => a.difference.compareTo(b.difference));
    final InsufficientData? insufficient = prevExp.isEmpty && prevInc.isEmpty
        ? InsufficientData.noPreviousData
        : curExp.length + prevExp.length < 3
        ? InsufficientData.tooFewEntries
        : null;
    return PeriodComparison(
      unit: unit,
      currentStart: curStart,
      currentEnd: curEnd,
      previousStart: prevStart,
      previousEnd: prevEnd,
      expense: ctx.sum(curExp),
      previousExpense: ctx.sum(prevExp),
      income: ctx.sum(curInc),
      previousIncome: ctx.sum(prevInc),
      increases: up.take(3).toList(),
      decreases: down.take(3).toList(),
      insufficient: insufficient,
    );
  }

  /// Start of the current [unit] and the whole previous one.
  static (DateTime, DateTime, DateTime) _bounds(
    AiContext ctx,
    PeriodUnit unit,
    DateTime today,
  ) {
    switch (unit) {
      case PeriodUnit.day:
        return (today, DateTime(today.year, today.month, today.day - 1), today);
      case PeriodUnit.week:
        final first = ctx.data.preferences.weekStart.clamp(1, 7);
        final back = (today.weekday - first) % 7;
        final s = DateTime(today.year, today.month, today.day - back);
        return (s, DateTime(s.year, s.month, s.day - 7), s);
      case PeriodUnit.month:
        final (ps, pe) = ctx.period(1);
        return (ctx.periodStart, ps, pe);
      case PeriodUnit.quarter:
        final s = DateTime(today.year, (today.month - 1) ~/ 3 * 3 + 1);
        return (s, DateTime(s.year, s.month - 3), s);
      case PeriodUnit.year:
        final s = DateTime(today.year);
        return (s, DateTime(s.year - 1), s);
    }
  }
}
