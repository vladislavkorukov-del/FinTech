import 'dart:math' as math;

import '../../../domain/finance_engine.dart';
import '../../../domain/models.dart';
import '../detectors/recurring_detector.dart';
import '../memory/personal_memory.dart';
import '../models/ai_models.dart';
import '../services/ai_context.dart';

/// The longer view of the money, from the person's own numbers: how the
/// dreams are going, what subscriptions cost, how long savings would last
/// and how steady things are. No investment, credit or tax advice.
abstract final class FinancialHealthEngine {
  /// Each dream at the current saving pace (the average of the last three
  /// months' contributions), with what its deadline needs.
  static List<GoalForecast> goals(AiContext ctx) {
    final out = <GoalForecast>[];
    final since = DateTime(ctx.now.year, ctx.now.month - 3, ctx.now.day);
    for (final g in ctx.data.goals) {
      if (g.currency != ctx.currency) continue;
      final saved = FinanceEngine.goalSaved(g, ctx.data.entries);
      final left = math.max(0, g.targetMinor - saved);
      final recent = FinanceEngine.goalContributions(g, ctx.data.entries)
          .where((e) => !e.date.isBefore(since))
          .fold<int>(0, (a, e) => a + (e.destinationMinor ?? e.amountMinor));
      final pace = (recent / 3).round();
      final need = g.deadline == null
          ? null
          : FinanceEngine.savingsPace(g, saved, now: ctx.now)?.month;
      DateTime? expected;
      if (left > 0 && pace > 0) {
        final months = (left / pace).ceil();
        expected = DateTime(ctx.now.year, ctx.now.month + months, ctx.now.day);
      }
      out.add(
        GoalForecast(
          goal: g,
          saved: saved,
          left: left,
          monthlyPace: pace,
          monthlyNeed: need,
          expectedDate: left <= 0 ? ctx.now : expected,
        ),
      );
    }
    return out;
  }

  /// A monthly cost of a rule's payment.
  static double perMonth(int amount, String frequency, int interval) =>
      amount *
      switch (frequency) {
        'daily' => 30.4 / interval,
        'weekly' => 4.35 / interval,
        'yearly' => 1 / (12 * interval),
        _ => 1 / interval,
      };

  static double _perMonth(RecurringCandidate c) =>
      c.typicalAmount *
      switch (c.cadence) {
        Cadence.weekly => 4.35,
        Cadence.biweekly => 2.17,
        Cadence.monthly => 1,
        Cadence.quarterly => 1 / 3,
        Cadence.yearly => 1 / 12,
      };

  /// What subscriptions cost: the app's subscriptions plus found ones the
  /// person confirmed; new ones, changed prices and stopped ones.
  static SubscriptionAnalytics subscriptions(
    AiContext ctx, {
    PersonalMemory? memory,
  }) {
    final rules = ctx.data.recurring.where(
      (r) =>
          r.enabled &&
          r.kind == EntryKind.expense &&
          r.paymentType == 'subscription' &&
          r.currency == ctx.currency,
    );
    var monthly = 0.0;
    var count = 0;
    for (final r in rules) {
      monthly += perMonth(r.amountMinor, r.frequency, r.interval);
      count++;
    }
    final all = RecurringDetector.detect(
      ctx,
      memory: memory,
      includeStopped: true,
    ).where((c) => c.nature == PaymentNature.subscription).toList();
    for (final c in all) {
      if (c.stopped || c.tracked) continue;
      if (memory?.confirmedSubscriptions.contains(c.merchantKey) ?? false) {
        monthly += _perMonth(c);
        count++;
      }
    }
    final recent = ctx.now.subtract(const Duration(days: 45));
    return SubscriptionAnalytics(
      monthly: (monthly / 100).round() * 100,
      count: count,
      added: [
        for (final c in all)
          if (!c.stopped && (c.firstDate?.isAfter(recent) ?? false)) c,
      ],
      priceChanged: [
        for (final c in all)
          if (!c.stopped && c.amountChanged) c,
      ],
      stopped: [
        for (final c in all)
          if (c.stopped && c.silentDays < 400) c,
      ],
    );
  }

  /// Savings (savings and deposit accounts) against typical monthly
  /// spending and obligations. Null without savings or spending history.
  static Cushion? cushion(AiContext ctx) {
    var savings = 0;
    for (final a in ctx.data.accounts) {
      if (a.archived || a.currency != ctx.currency) continue;
      if (a.type != 'savings' && a.type != 'deposit') continue;
      savings += FinanceEngine.balance(a, ctx.data.entries);
    }
    final months = [
      for (final back in ctx.fullPeriodsWithData.take(3))
        ctx.sum(ctx.expensesIn(ctx.period(back).$1, ctx.period(back).$2)),
    ];
    if (savings <= 0 || months.isEmpty) return null;
    var mandatory = 0.0;
    for (final r in ctx.data.recurring) {
      if (!r.enabled ||
          r.kind != EntryKind.expense ||
          r.paymentType != 'mandatory' ||
          r.currency != ctx.currency) {
        continue;
      }
      mandatory += perMonth(r.amountMinor, r.frequency, r.interval);
    }
    return Cushion(
      savings: savings,
      monthlyExpenses: median(months).round(),
      monthlyMandatory: mandatory.round(),
    );
  }

  /// The stability index with its reasons. Needs two full months.
  static StabilityScore? stability(
    AiContext ctx, {
    required IncomeStability? income,
    required Cushion? cushion,
  }) {
    final periods = ctx.fullPeriodsWithData.take(3).toList();
    if (periods.length < 2) return null;
    final factors = <StabilityFactor>[];
    factors.add(switch (income) {
      IncomeStability.stable => const StabilityFactor(
        'Доходы',
        25,
        25,
        'приходят ровно',
      ),
      IncomeStability.moderate => const StabilityFactor(
        'Доходы',
        16,
        25,
        'немного колеблются',
      ),
      IncomeStability.volatile => const StabilityFactor(
        'Доходы',
        6,
        25,
        'сильно меняются от месяца к месяцу',
      ),
      null => const StabilityFactor('Доходы', 10, 25, 'пока мало данных'),
    });
    // Cash flow: how many recent months ended with more coming in.
    var positive = 0;
    var income3 = 0, expense3 = 0;
    for (final back in periods) {
      final (s, e) = ctx.period(back);
      final inc = ctx.sum(ctx.incomesIn(s, e));
      final exp = ctx.sum(ctx.expensesIn(s, e));
      income3 += inc;
      expense3 += exp;
      if (inc > exp) positive++;
    }
    final cashPoints = (25 * positive / periods.length).round();
    factors.add(
      StabilityFactor(
        'Денежный поток',
        cashPoints,
        25,
        'в плюсе $positive из ${periods.length} последних месяцев',
      ),
    );
    final months = cushion?.months;
    final cushionPoints = months == null
        ? 0
        : (25 * math.min(months, 6) / 6).round();
    factors.add(
      StabilityFactor(
        'Подушка',
        cushionPoints,
        25,
        months == null
            ? 'накоплений на отдельных счетах нет'
            : 'хватит примерно на ${months.toStringAsFixed(1).replaceAll('.', ',')} мес.',
      ),
    );
    final monthlyIncome = income3 / periods.length;
    final mandatory = cushion?.monthlyMandatory ?? 0;
    final share = monthlyIncome <= 0 ? 1.0 : mandatory / monthlyIncome;
    final obligationPoints = (25 * (1 - ((share - .3) / .4).clamp(0, 1)))
        .round();
    factors.add(
      StabilityFactor(
        'Обязательные платежи',
        obligationPoints,
        25,
        monthlyIncome <= 0
            ? 'доходов не видно'
            : 'около ${(share * 100).round()}% дохода',
      ),
    );
    if (expense3 == 0 && income3 == 0) return null;
    return StabilityScore(factors);
  }
}
