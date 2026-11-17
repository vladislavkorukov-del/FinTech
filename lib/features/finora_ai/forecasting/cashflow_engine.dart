import '../../../domain/finance_engine.dart';
import '../../../domain/models.dart';
import '../detectors/anomaly_detector.dart';
import '../models/ai_models.dart';
import '../services/ai_context.dart';

/// Money flows for the rest of the period: regular payments and incomes
/// still due (from the app's own regular payments), and the everyday
/// spending pace (without one-off purchases and regular payments).
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
}
