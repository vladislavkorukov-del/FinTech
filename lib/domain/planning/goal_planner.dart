import '../finance_engine.dart';
import '../models.dart';

/// One goal in a funding plan.
class GoalProjection {
  const GoalProjection({
    required this.goal,
    required this.savedMinor,
    required this.leftMinor,
    required this.allocatedMinor,
    required this.plannedMinor,
    required this.date,
    required this.needMonthlyMinor,
    required this.reason,
  });
  final Goal goal;
  final int savedMinor, leftMinor;

  /// What the goal really gets per month after the budget is shared.
  final int allocatedMinor;

  /// What the person planned for it.
  final int plannedMinor;

  /// When it is reached; null — not reachable with these inputs.
  final DateTime? date;

  /// What it would need per month to make its deadline (null — no deadline).
  final int? needMonthlyMinor;

  /// Why there is no date, or what the date depends on.
  final String reason;
  bool get done => leftMinor <= 0;
}

/// The goals budget shared out, and what it leaves uncovered.
class GoalPlanResult {
  const GoalPlanResult(this.goals, this.budgetMinor, this.plannedMinor);
  final List<GoalProjection> goals;
  final int budgetMinor, plannedMinor;

  /// Planned contributions the budget cannot pay (0 — all covered).
  int get deficitMinor => budgetMinor > 0 && plannedMinor > budgetMinor
      ? plannedMinor - budgetMinor
      : 0;

  GoalProjection? of(String goalId) =>
      goals.where((g) => g.goal.id == goalId).firstOrNull;
}

/// A change of one goal's date between two plans.
class GoalShift {
  const GoalShift(this.goal, this.before, this.after);
  final Goal goal;
  final DateTime? before, after;

  /// Days later (+) or sooner (−); null when one of the dates is unknown.
  int? get days => before == null || after == null
      ? null
      : after!.difference(before!).inDays;
}

/// Goal funding (Phase 8, «Конфликт целей»): one monthly budget for goals,
/// shared by protection, then priority. Money is never counted twice: a
/// kopeck goes to one goal only; when the budget is short, the last goals
/// get less (or nothing) and the shortfall is shown. A reached goal's money
/// is not moved on by itself (a rule may suggest it). Dates use a steady
/// daily pace of the monthly contribution; a goal with no contribution has
/// no date. Re-planning changes no account — it is a plan, not a transfer.
abstract final class GoalPlanner {
  static GoalPlanResult plan(
    FinanceData data, {
    GoalFunding? funding,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final f = funding ?? data.extras.goalFunding;
    final goals = data.goals.toList();
    final plans = {for (final g in goals) g.id: f.planFor(g.id)};
    final saved = {
      for (final g in goals) g.id: FinanceEngine.goalSaved(g, data.entries),
    };
    bool open(Goal g) => g.targetMinor > saved[g.id]!;
    final planned = goals
        .where(open)
        .fold<int>(0, (a, g) => a + plans[g.id]!.monthlyMinor);
    // Order of funding: protected first, then priority, then the plan order.
    final order = goals.where(open).toList()
      ..sort((a, b) {
        final pa = plans[a.id]!, pb = plans[b.id]!;
        if (pa.protected != pb.protected) return pa.protected ? -1 : 1;
        return pa.priority.compareTo(pb.priority);
      });
    var room = f.budgetMinor > 0 ? f.budgetMinor : planned;
    final allocated = <String, int>{};
    for (final g in order) {
      final want = plans[g.id]!.monthlyMinor;
      final give = want <= room ? want : room;
      allocated[g.id] = give < 0 ? 0 : give;
      room -= allocated[g.id]!;
    }
    final out = <GoalProjection>[];
    for (final g in goals) {
      final s = saved[g.id]!;
      final left = g.targetMinor - s;
      final give = allocated[g.id] ?? 0;
      final want = plans[g.id]!.monthlyMinor;
      DateTime? date;
      var reason = '';
      if (left <= 0) {
        date = clock;
        reason = 'накоплено';
      } else if (give <= 0) {
        reason = want > 0
            ? 'бюджета на цели не хватает — взнос не покрыт'
            : 'нет ежемесячного взноса';
      } else {
        date = clock.add(Duration(days: daysFor(left, give)));
        if (give < want) reason = 'взнос покрыт частично';
      }
      int? need;
      if (g.deadline != null && left > 0) {
        final months = monthsBetween(clock, g.deadline!);
        need = months <= 0 ? left : (left + months - 1) ~/ months;
      }
      out.add(
        GoalProjection(
          goal: g,
          savedMinor: s,
          leftMinor: left < 0 ? 0 : left,
          allocatedMinor: give,
          plannedMinor: want,
          date: date,
          needMonthlyMinor: need,
          reason: reason,
        ),
      );
    }
    return GoalPlanResult(out, f.budgetMinor, planned);
  }

  /// Days to collect [leftMinor] at [monthlyMinor] a month (12 months = 365
  /// days), rounded up. Whole numbers only.
  static int daysFor(int leftMinor, int monthlyMinor) =>
      (leftMinor * 365 + monthlyMinor * 12 - 1) ~/ (monthlyMinor * 12);

  /// Whole months from [a] to [b] (at least 0).
  static int monthsBetween(DateTime a, DateTime b) {
    var m = (b.year - a.year) * 12 + b.month - a.month;
    if (b.day < a.day) m--;
    return m < 0 ? 0 : m;
  }

  /// How every goal's date moves from [before] to [after].
  static List<GoalShift> compare(GoalPlanResult before, GoalPlanResult after) =>
      [
        for (final g in after.goals)
          if (!g.done) GoalShift(g.goal, before.of(g.goal.id)?.date, g.date),
      ];
}
