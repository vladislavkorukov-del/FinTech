import '../../../domain/models.dart';
import '../detectors/anomaly_detector.dart';
import '../detectors/recurring_detector.dart';
import '../forecasting/cashflow_engine.dart';
import '../forecasting/forecast_engine.dart';
import '../insights/budget_risk_engine.dart';
import '../insights/financial_health_engine.dart';
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
    required this.regularIncome,
    required this.timeline,
    required this.frequency,
    required this.goalForecasts,
    required this.subscriptionStats,
    required this.cushion,
    required this.stability,
    this.memory,
  });

  factory FinoraAiSnapshot.compute(
    FinanceData data, {
    PersonalMemory? memory,
    DateTime? now,
    DateTime? periodStart,
  }) {
    final ctx = AiContext(
      data,
      now: now,
      periodStart: periodStart,
      excludedMonths: memory?.excludedMonths ?? const {},
    );
    final patterns = FinancialPatternEngine.compute(ctx);
    final cushion = FinancialHealthEngine.cushion(ctx);
    final anomalies = AnomalyDetector.detect(ctx);
    final recurring = RecurringDetector.detect(ctx, memory: memory);
    final regularIncome = RecurringDetector.detect(
      ctx,
      memory: memory,
      kind: EntryKind.income,
    );
    return FinoraAiSnapshot._(
      memory: memory,
      regularIncome: regularIncome,
      timeline: CashflowEngine.timeline(
        ctx,
        anomalies: anomalies,
        found: [...recurring, ...regularIncome],
      ),
      frequency: AnomalyDetector.frequency(ctx),
      goalForecasts: FinancialHealthEngine.goals(ctx),
      subscriptionStats: FinancialHealthEngine.subscriptions(
        ctx,
        memory: memory,
      ),
      cushion: cushion,
      stability: FinancialHealthEngine.stability(
        ctx,
        income: patterns.incomeStability,
        cushion: cushion,
      ),
      ctx: ctx,
      comparison: MonthComparisonEngine.compute(ctx),
      aboveUsual: MonthComparisonEngine.aboveUsual(ctx),
      forecast: ForecastEngine.compute(ctx, anomalies: anomalies),
      cashflow: CashflowEngine.compute(ctx, anomalies: anomalies),
      anomalies: anomalies,
      recurring: recurring,
      subscriptions: RecurringDetector.subscriptions(ctx, memory: memory),
      risks: BudgetRiskEngine.compute(ctx, anomalies: anomalies),
      patterns: patterns,
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

  /// Incomes that come at a steady rhythm (salary and the like).
  final List<RecurringCandidate> regularIncome;

  /// The rest of the period day by day, with late regular payments.
  final CashflowTimeline timeline;
  final FrequencyAnomaly? frequency;

  /// Each dream at the current pace; subscriptions' costs and changes; how
  /// long savings would last; the stability index with its reasons.
  final List<GoalForecast> goalForecasts;
  final SubscriptionAnalytics subscriptionStats;
  final Cushion? cushion;
  final StabilityScore? stability;

  /// The person's memory (snoozed insights, rejections), when known.
  final PersonalMemory? memory;

  /// Every insight, deduplicated, without snoozed ones, most relevant first.
  late final List<Insight> insights = InsightEngine.build(this);

  /// The few insights worth showing first: better three useful ones than
  /// twenty small ones.
  List<Insight> get top => InsightEngine.top(insights);

  /// Any period against the previous one (see
  /// [MonthComparisonEngine.comparePeriods]).
  PeriodComparison compare(PeriodUnit unit) =>
      MonthComparisonEngine.comparePeriods(ctx, unit: unit);
}
