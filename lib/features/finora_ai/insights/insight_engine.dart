import '../models/ai_models.dart';
import '../services/finora_ai_snapshot.dart';

/// Turns the engines' results into a ranked list of insights. It does no
/// arithmetic of its own: every number comes from a snapshot field, and an
/// insight is only made when its engine had enough data.
abstract final class InsightEngine {
  static List<Insight> build(FinoraAiSnapshot s) {
    final out = <Insight>[];
    final c = s.comparison;
    if (s.ctx.expenses.length < 5) {
      return const [Insight(kind: InsightKind.notEnoughData, priority: 100)];
    }
    // Month summary.
    out.add(
      Insight(
        kind: InsightKind.summary,
        priority: 90,
        amount: c.current,
        secondAmount: c.insufficient == null ? c.previous : null,
        percent: c.insufficient == null ? c.percent : null,
        categoryId: c.drivers.isEmpty ? null : c.drivers.first.categoryId,
      ),
    );
    // Forecast and free money.
    final f = s.forecast;
    if (f.insufficient == null) {
      out.add(
        Insight(
          kind: InsightKind.forecast,
          priority: 80,
          amount: f.projectedExpense,
          secondAmount: f.projectedBalance,
        ),
      );
    }
    if (s.cashflow.mandatory > 0 || f.insufficient == null) {
      out.add(
        Insight(
          kind: InsightKind.freeMoney,
          priority: 78,
          amount: s.cashflow.afterMandatory,
          secondAmount: f.insufficient == null ? s.cashflow.afterAll : null,
        ),
      );
    }
    // Budget risks: likely overruns only.
    for (final r in s.risks) {
      if (r.probability < .6 || r.overrun <= 0) continue;
      out.add(
        Insight(
          kind: InsightKind.budgetRisk,
          priority: 75 + (r.probability * 10).round(),
          risk: r,
          categoryId: r.budget.categoryId,
          amount: r.overrun,
          percent: r.probability * 100,
        ),
      );
    }
    // Growth: what drives the change against last period, and categories
    // above their usual level.
    if (c.insufficient == null) {
      for (final d in c.drivers.take(2)) {
        out.add(
          Insight(
            kind: InsightKind.growth,
            priority: 70,
            categoryId: d.categoryId,
            amount: d.difference,
            percent: d.percent,
          ),
        );
      }
      for (final d in c.decreases.take(1)) {
        out.add(
          Insight(
            kind: InsightKind.decrease,
            priority: 50,
            categoryId: d.categoryId,
            amount: -d.difference,
            percent: d.percent?.abs(),
          ),
        );
      }
    }
    for (final u in s.aboveUsual.take(2)) {
      if (c.drivers.any((d) => d.categoryId == u.categoryId)) continue;
      out.add(
        Insight(
          kind: InsightKind.growth,
          priority: 66,
          categoryId: u.categoryId,
          amount: u.difference,
          subject: 'usual',
        ),
      );
    }
    // Possible subscriptions and unusual expenses.
    for (final sub in s.subscriptions.take(3)) {
      out.add(
        Insight(
          kind: InsightKind.subscription,
          priority: 64,
          recurring: sub,
          amount: sub.typicalAmount,
          subject: sub.displayName,
        ),
      );
    }
    for (final a in s.anomalies.take(2)) {
      out.add(
        Insight(
          kind: InsightKind.anomaly,
          priority: 62,
          anomaly: a,
          amount: a.entry.amountMinor,
          secondAmount: a.typical,
          categoryId: a.entry.categoryId,
          subject: a.entry.payee,
        ),
      );
    }
    // Longer patterns.
    for (final t in s.patterns.trends.take(2)) {
      out.add(
        Insight(
          kind: InsightKind.trend,
          priority: t.trend == Trend.rising ? 58 : 45,
          trend: t,
          categoryId: t.categoryId,
        ),
      );
    }
    final stability = s.patterns.incomeStability;
    if (stability != null) {
      out.add(
        Insight(
          kind: InsightKind.incomeStability,
          priority: stability == IncomeStability.volatile ? 55 : 30,
          subject: stability.name,
        ),
      );
    }
    for (final m in s.patterns.unusualMonths.reversed.take(1)) {
      out.add(
        Insight(
          kind: InsightKind.unusualMonth,
          priority: 35,
          amount: m.total,
          secondAmount: m.average,
          subject: m.month.toIso8601String(),
        ),
      );
    }
    final h = s.patterns.habits;
    if (h.busiestWeekday != null && h.weekdayShare >= .25) {
      out.add(
        Insight(
          kind: InsightKind.habit,
          priority: 28,
          subject: '${h.busiestWeekday}',
          percent: h.weekdayShare * 100,
        ),
      );
    }
    for (final b in s.budgetSuggestions.take(2)) {
      out.add(
        Insight(
          kind: InsightKind.suggestion,
          priority: 40,
          categoryId: b.categoryId,
          amount: b.limit,
        ),
      );
    }
    for (final (goal, month) in s.goalNeeds.take(2)) {
      out.add(
        Insight(
          kind: InsightKind.goal,
          priority: 42,
          subject: goal.name,
          amount: month,
          secondAmount: s.cashflow.afterAll,
        ),
      );
    }
    out.sort((a, b) => b.priority.compareTo(a.priority));
    return out;
  }
}
