import '../../../domain/finance_engine.dart';
import '../../../domain/models.dart';
import '../detectors/anomaly_detector.dart';
import '../models/ai_models.dart';
import '../services/ai_context.dart';

/// Money flows for the rest of the period: regular payments and incomes
/// still due (from the app's own regular payments), and the everyday
/// spending pace (without one-off purchases and regular payments).
/// [timeline] lays them out day by day, together with regular payments
/// Finora found in the history but the app does not track yet.
abstract final class CashflowEngine {
  /// Occurrences of enabled regular payments of [kind] due before the end
  /// of the period (overdue ones that were not confirmed count too).
  static List<(RecurringRule, DateTime)> upcoming(
    AiContext ctx,
    EntryKind kind,
  ) {
    final out = <(RecurringRule, DateTime)>[];
    for (final r in ctx.data.recurring) {
      if (!r.enabled || r.kind != kind || r.currency != ctx.currency) continue;
      var rule = r;
      for (var guard = 0; guard < 40; guard++) {
        if (!rule.nextDate.isBefore(ctx.periodEnd)) break;
        out.add((r, rule.nextDate));
        try {
          rule = rule.copyWith(nextDate: FinanceEngine.nextOccurrence(rule));
        } on FormatException {
          break;
        }
      }
    }
    return out;
  }

  static int upcomingTotal(AiContext ctx, EntryKind kind) =>
      upcoming(ctx, kind).fold(0, (a, e) => a + e.$1.amountMinor);

  /// Whether [e] is one of the regular payments (by name or service).
  static bool isRegular(AiContext ctx, FinanceEntry e) {
    final key = AiContext.merchantKey(e.payee);
    return ctx.data.recurring.any(
      (r) =>
          (key.isNotEmpty && AiContext.merchantKey(r.name) == key) ||
          (r.serviceId != null && r.serviceId == e.serviceId),
    );
  }

  /// Everyday spending of [list]: without regular payments and one-offs.
  static int variable(
    AiContext ctx,
    Iterable<FinanceEntry> list,
    List<Anomaly> anomalies,
  ) => list
      .where(
        (e) => !isRegular(ctx, e) && !AnomalyDetector.isOneOff(e, anomalies),
      )
      .fold(0, (a, e) => a + e.amountMinor);

  /// Daily everyday pace: this period's pace blended with the last full
  /// periods' (the further into the period, the more this period counts).
  /// Null when there is neither enough of this period nor any history.
  static double? dailyPace(AiContext ctx, List<Anomaly> anomalies) {
    final current =
        variable(
          ctx,
          ctx.expensesIn(ctx.periodStart, ctx.periodEnd),
          anomalies,
        ) /
        ctx.daysPassed;
    final past = <double>[];
    for (final back in ctx.fullPeriodsWithData.take(3)) {
      final (s, e) = ctx.period(back);
      past.add(
        variable(ctx, ctx.expensesIn(s, e), const []) / e.difference(s).inDays,
      );
    }
    if (past.isEmpty) {
      // Without history the pace needs a week and a handful of expenses —
      // a pace of zero from an empty ledger is not a forecast.
      final count = ctx.expensesIn(ctx.periodStart, ctx.periodEnd).length;
      return ctx.daysPassed >= 7 && count >= 5 ? current : null;
    }
    final history = past.reduce((a, b) => a + b) / past.length;
    if (ctx.daysPassed < 3) return history;
    final w = (ctx.daysPassed / ctx.periodDays).clamp(.25, .85);
    return current * w + history * (1 - w);
  }

  static Cashflow compute(AiContext ctx, {List<Anomaly>? anomalies}) {
    final a = anomalies ?? AnomalyDetector.detect(ctx);
    final pace = dailyPace(ctx, a);
    final due = upcoming(ctx, EntryKind.expense);
    return Cashflow(
      balance: ctx.balance,
      mandatory: due.fold(0, (s, e) => s + e.$1.amountMinor),
      // An estimate: whole rubles.
      expectedVariable: pace == null
          ? 0
          : (pace * ctx.daysLeft / 100).round() * 100,
      expectedIncome: upcomingTotal(ctx, EntryKind.income),
      payments: [for (final d in due) d.$1],
    );
  }

  /// The rest of the period as dated events and a projected balance per
  /// day. Found regular payments are added only when the app has no rule
  /// for them, with the detector's confidence; ones that usually would have
  /// happened by now are listed as [CashflowTimeline.late].
  static CashflowTimeline timeline(
    AiContext ctx, {
    List<Anomaly>? anomalies,
    List<RecurringCandidate> found = const [],
  }) {
    final today = DateTime(ctx.now.year, ctx.now.month, ctx.now.day);
    final events = <CashflowEvent>[];
    final late = <CashflowEvent>[];
    for (final kind in [EntryKind.expense, EntryKind.income]) {
      for (final (rule, date) in upcoming(ctx, kind)) {
        final overdue = date.isBefore(today);
        final event = CashflowEvent(
          date: overdue ? today : date,
          amount: rule.amountMinor,
          kind: kind,
          type: kind == EntryKind.income
              ? CashflowEventType.income
              : rule.paymentType == 'subscription'
              ? CashflowEventType.subscription
              : CashflowEventType.mandatory,
          title: rule.name,
          confidence: 1,
          detected: false,
          categoryId: rule.categoryId,
          late: overdue,
        );
        events.add(event);
        if (overdue) late.add(event);
      }
    }
    for (final c in found) {
      if (c.tracked || c.confidence < .5) continue;
      final event = CashflowEvent(
        date: c.nextExpected.isBefore(today) ? today : c.nextExpected,
        amount: c.typicalAmount,
        kind: c.kind,
        type: c.kind == EntryKind.income
            ? CashflowEventType.income
            : c.subscriptionLikely
            ? CashflowEventType.subscription
            : CashflowEventType.recurring,
        title: c.displayName,
        confidence: c.confidence,
        detected: true,
        categoryId: c.categoryId,
        late: c.isLate(ctx.now),
      );
      if (event.late) {
        late.add(event);
      } else if (!c.nextExpected.isBefore(today) &&
          c.nextExpected.isBefore(ctx.periodEnd)) {
        events.add(event);
      }
    }
    events.sort((a, b) => a.date.compareTo(b.date));
    final pace = dailyPace(ctx, anomalies ?? AnomalyDetector.detect(ctx));
    final balances = <(DateTime, int)>[];
    if (pace != null) {
      var balance = ctx.balance.toDouble();
      for (
        var day = today;
        day.isBefore(ctx.periodEnd);
        day = DateTime(day.year, day.month, day.day + 1)
      ) {
        for (final e in events) {
          if (e.date == day) balance += e.signed;
        }
        balance -= pace;
        balances.add((day, (balance / 100).round() * 100));
      }
    }
    return CashflowTimeline(events: events, balances: balances, late: late);
  }
}
