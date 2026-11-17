import '../../../domain/models.dart';
import '../detectors/anomaly_detector.dart';
import '../detectors/recurring_detector.dart';
import '../forecasting/cashflow_engine.dart';
import '../forecasting/forecast_engine.dart';
import '../insights/budget_risk_engine.dart';
import '../insights/financial_pattern_engine.dart';
import '../insights/insight_engine.dart';
import '../insights/month_comparison_engine.dart';
import '../insights/recommendation_engine.dart';
import '../memory/personal_memory.dart';
import '../models/ai_models.dart';
import 'ai_context.dart';

/// Everything Finora knows about the person's money right now, computed
/// once by the engines. The UI and the response layer read from here only.
class FinoraAiSnapshot {
  FinoraAiSnapshot._({
    required this.ctx,
    required this.comparison,
    required this.aboveUsual,
    required this.forecast,
    required this.cashflow,
    required this.anomalies,
    required this.recurring,
    required this.subscriptions,
    required this.risks,
    required this.patterns,
    required this.budgetSuggestions,
    required this.goalNeeds,
  });

  factory FinoraAiSnapshot.compute(
    FinanceData data, {
    PersonalMemory? memory,
    DateTime? now,
    DateTime? periodStart,
  }) {
    final ctx = AiContext(data, now: now, periodStart: periodStart);
    final anomalies = AnomalyDetector.detect(ctx);
    final recurring = RecurringDetector.detect(ctx, memory: memory);
    return FinoraAiSnapshot._(
      ctx: ctx,
      comparison: MonthComparisonEngine.compute(ctx),
      aboveUsual: MonthComparisonEngine.aboveUsual(ctx),
      forecast: ForecastEngine.compute(ctx, anomalies: anomalies),
      cashflow: CashflowEngine.compute(ctx, anomalies: anomalies),
      anomalies: anomalies,
      recurring: recurring,
      subscriptions: RecurringDetector.subscriptions(ctx, memory: memory),
      risks: BudgetRiskEngine.compute(ctx, anomalies: anomalies),
      patterns: FinancialPatternEngine.compute(ctx),
      budgetSuggestions: RecommendationEngine.budgets(ctx, memory: memory),
      goalNeeds: RecommendationEngine.goalNeeds(ctx),
    );
  }

  final AiContext ctx;
  final MonthComparison comparison;
  final List<CategoryChange> aboveUsual;
  final Forecast forecast;
  final Cashflow cashflow;
  final List<Anomaly> anomalies;
  final List<RecurringCandidate> recurring, subscriptions;
  final List<BudgetRisk> risks;
  final Patterns patterns;
  final List<BudgetSuggestion> budgetSuggestions;
  final List<(Goal, int)> goalNeeds;

  late final List<Insight> insights = InsightEngine.build(this);
}
