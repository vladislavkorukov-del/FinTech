import '../memory/personal_memory.dart';
import '../models/ai_models.dart';
import '../services/ai_context.dart';
import '../services/finora_ai_snapshot.dart';

/// Turns the engines' results into a ranked list of insights. It does no
/// arithmetic of its own: every number comes from a snapshot field, and an
/// insight is only made when its engine had enough data.
///
/// Each insight carries its confidence and a trace (engine, reason, input
/// period, related operations). The list is deduplicated (one insight per
/// fact and subject), insights the person snoozed are left out until their
/// cooldown ends, and the rest is ranked by relevance — priority weighed by
/// confidence. [top] keeps only the few worth showing first.
abstract final class InsightEngine {
  /// How many insights to show at first.
  static const topCount = 3;

  /// Below this confidence an insight is not shown at all.
  static const minConfidence = .4;

  static List<Insight> top(List<Insight> all) => [
    for (final i in all)
      if (i.kind != InsightKind.summary) i,
  ].take(topCount).toList();

  static List<Insight> build(FinoraAiSnapshot s) {
    final out = <Insight>[];
    final c = s.comparison;
    final ctx = s.ctx;
    InsightTrace trace(
      String engine,
      String reason, {
      Iterable<String> related = const [],
      DateTime? from,
      DateTime? to,
    }) => InsightTrace(
      sourceEngine: engine,
      reason: reason,
      periodStart: from ?? ctx.periodStart,
      periodEnd: to ?? ctx.periodEnd,
      relatedEntryIds: related.toList(),
      generatedAt: ctx.now,
    );
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
        trace: trace('MonthComparisonEngine', 'same-days:${c.comparableDays}'),
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
          confidence: f.confidence,
          trace: trace('ForecastEngine', 'pace-blend'),
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
          confidence: f.insufficient == null ? f.confidence : .9,
          trace: trace(
            'CashflowEngine',
            'balance-minus-due:${s.cashflow.payments.length}',
          ),
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
          confidence: r.probability,
          trace: trace('BudgetRiskEngine', 'pace-vs-limit'),
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
            confidence: .9,
            trace: trace('MonthComparisonEngine', 'category-driver'),
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
            confidence: .9,
            trace: trace('MonthComparisonEngine', 'category-decrease'),
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
          confidence: .8,
          trace: trace('MonthComparisonEngine', 'above-median-3'),
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
          confidence: sub.confidence,
          trace: trace(
            'RecurringDetector',
            'cadence:${sub.cadence.name}:${sub.occurrences}',
            from: sub.lastDate,
          ),
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
          // A norm resting on more payments is firmer.
          confidence: (.55 + a.history / 30).clamp(.55, .95),
          trace: trace(
            'AnomalyDetector',
            '${a.basis.name}-median:${a.history}',
            related: [a.entry.id],
          ),
        ),
      );
    }
    final freq = s.frequency;
    if (freq != null) {
      out.add(
        Insight(
          kind: InsightKind.frequency,
          priority: 52,
          amount: freq.count,
          secondAmount: freq.typical,
          confidence: .7,
          trace: trace('AnomalyDetector', 'count-vs-median-periods'),
        ),
      );
    }
    // Regular payments that usually would have happened by now (detected
    // ones; the app's own overdue payments are shown on the home screen).
    for (final e in s.timeline.late.where((e) => e.detected).take(2)) {
      out.add(
        Insight(
          kind: InsightKind.latePayment,
          priority: 60,
          subject: e.title,
          amount: e.amount,
          categoryId: e.categoryId,
          confidence: e.confidence * .85,
          trace: trace('CashflowEngine', 'late-vs-rhythm'),
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
          confidence: .7,
          trace: trace('FinancialPatternEngine', 'trend-3-months'),
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
          confidence: .7,
          trace: trace('FinancialPatternEngine', 'income-variation'),
        ),
      );
    }
    for (final m
        in s.patterns.unusualMonths.reversed
            .where(
              (m) =>
                  !(s.memory?.isRejected(
                        'unusual:${AiContext.monthKey(m.month)}',
                      ) ??
                      false),
            )
            .take(1)) {
      out.add(
        Insight(
          kind: InsightKind.unusualMonth,
          priority: 35,
          amount: m.total,
          secondAmount: m.average,
          subject: m.month.toIso8601String(),
          confidence: .6,
          trace: trace('FinancialPatternEngine', 'month-vs-average'),
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
          confidence: .55,
          trace: trace('FinancialPatternEngine', 'weekday-share'),
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
          confidence: .65,
          trace: trace('RecommendationEngine', 'median-${b.basedOnMonths}'),
        ),
      );
    }
    // Dreams: what the deadline needs, and whether the pace keeps up.
    for (final g in s.goalForecasts.where((g) => !g.done).take(2)) {
      final need = g.monthlyNeed;
      if (need == null && g.expectedDate == null) continue;
      out.add(
        Insight(
          kind: InsightKind.goal,
          priority: need != null && (g.deviation ?? 0) < 0 ? 57 : 42,
          subject: g.goal.name,
          amount: need ?? g.monthlyPace,
          secondAmount: g.monthlyPace,
          severity: need != null && (g.deviation ?? 0) < 0
              ? InsightSeverity.notice
              : null,
          confidence: g.monthlyPace > 0 ? .8 : .7,
          trace: trace('FinancialHealthEngine', 'goal-pace-3-months'),
        ),
      );
    }
    // A subscription got dearer.
    for (final c in s.subscriptionStats.priceChanged.take(1)) {
      out.add(
        Insight(
          kind: InsightKind.priceChange,
          priority: 54,
          recurring: c,
          subject: c.displayName,
          amount: c.lastAmount,
          secondAmount: c.typicalAmount,
          confidence: c.confidence,
          trace: trace('RecurringDetector', 'last-vs-median'),
        ),
      );
    }
    // Savings for less than a month of usual spending.
    final cushion = s.cushion;
    if (cushion?.months case final months? when months < 1) {
      out.add(
        Insight(
          kind: InsightKind.cushion,
          priority: 46,
          amount: cushion!.savings,
          secondAmount: cushion.monthlyExpenses,
          percent: months * 100,
          confidence: .75,
          trace: trace('FinancialHealthEngine', 'savings-vs-median-month'),
        ),
      );
    }
    return rank(out, memory: s.memory, now: ctx.now);
  }

  /// Drops weak and snoozed insights, keeps the strongest of each fact
  /// about the same subject, and sorts by relevance.
  static List<Insight> rank(
    List<Insight> all, {
    PersonalMemory? memory,
    required DateTime now,
  }) {
    final best = <String, Insight>{};
    for (final i in all) {
      if (i.confidence < minConfidence) continue;
      if (memory?.isSnoozed(i.dedupKey, now) ?? false) continue;
      final seen = best[i.dedupKey];
      if (seen == null || i.relevance > seen.relevance) best[i.dedupKey] = i;
    }
    return best.values.toList()
      ..sort((a, b) => b.relevance.compareTo(a.relevance));
  }
}
