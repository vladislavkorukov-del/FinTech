import '../../../domain/models.dart';
import '../detectors/anomaly_detector.dart';
import '../models/ai_models.dart';
import '../services/ai_context.dart';
import 'cashflow_engine.dart';

/// Forecast for the end of the current period: expenses, income and the
/// balance, from what is already spent, the everyday pace and the regular
/// payments and incomes still due. Without enough data it says so.
abstract final class ForecastEngine {
  /// Rounds an estimate in kopecks to whole rubles.
  static int _rub(double minor) => (minor / 100).round() * 100;

  static Forecast compute(AiContext ctx, {List<Anomaly>? anomalies}) {
    final a = anomalies ?? AnomalyDetector.detect(ctx);
    final spent = ctx.sum(ctx.expensesIn(ctx.periodStart, ctx.periodEnd));
    final earned = ctx.sum(ctx.incomesIn(ctx.periodStart, ctx.periodEnd));
    final pace = CashflowEngine.dailyPace(ctx, a);
    final mandatory = CashflowEngine.upcomingTotal(ctx, EntryKind.expense);
    final regularIncome = CashflowEngine.upcomingTotal(ctx, EntryKind.income);
    final balance = ctx.balance;
    if (pace == null) {
      return Forecast(
        spentSoFar: spent,
        projectedExpense: spent + mandatory,
        incomeSoFar: earned,
        projectedIncome: earned + regularIncome,
        currentBalance: balance,
        projectedBalance: balance + regularIncome - mandatory,
        upcomingMandatory: mandatory,
        daysLeft: ctx.daysLeft,
        insufficient: Insufficient(
          ctx.expenses.isEmpty
              ? InsufficientReason.tooFewEntries
              : InsufficientReason.periodJustStarted,
        ),
      );
    }
    // Forecasts are estimates: whole rubles, no kopecks.
    final projectedExpense = _rub(spent + pace * ctx.daysLeft + mandatory);
    // Income: what came plus regular incomes due; when the last periods all
    // had income, their median is the floor (a salary not entered yet as a
    // regular payment still counts).
    final pastIncome = <int>[
      for (final back in [1, 2, 3])
        ctx.sum(ctx.incomesIn(ctx.period(back).$1, ctx.period(back).$2)),
    ];
    var projectedIncome = earned + regularIncome;
    if (pastIncome.every((v) => v > 0)) {
      final typical = median(pastIncome).round();
      if (typical > projectedIncome) projectedIncome = typical;
    }
    return Forecast(
      spentSoFar: spent,
      projectedExpense: projectedExpense,
      incomeSoFar: earned,
      projectedIncome: projectedIncome,
      currentBalance: balance,
      projectedBalance: _rub(
        (balance + (projectedIncome - earned) - (projectedExpense - spent))
            .toDouble(),
      ),
      upcomingMandatory: mandatory,
      daysLeft: ctx.daysLeft,
    );
  }
}
