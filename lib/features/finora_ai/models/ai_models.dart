import '../../../domain/models.dart';
import 'ai_results.dart';

export 'ai_results.dart';

/// Structured results of the Finora AI engines. Every number here is
/// computed from the person's own data by an engine; the response layer only
/// puts these numbers into words and can never change them.
///
/// A result that could not be computed honestly carries [Insufficient]
/// instead of a guess.

/// Why a result is missing: not enough history, nothing to compare, etc.
class Insufficient {
  const Insufficient(this.reason);
  final InsufficientReason reason;
}

enum InsufficientReason {
  /// Too few operations to say anything.
  tooFewEntries,

  /// No previous period to compare with.
  noPreviousPeriod,

  /// The period has only just started.
  periodJustStarted,

  /// The category cannot be determined with enough confidence.
  lowConfidence,
}

/// Where a classification came from, most trusted first:
/// personal_memory, exact_rule, statistical_rule (the merchant's history),
/// merchant_rule (the store and service catalog), ml_model, fallback.
enum ClassificationSource {
  memory,
  exact,
  history,
  catalog,
  model,
  fallback,
  none,
}

extension ClassificationSourceName on ClassificationSource {
  /// The name used in traces and explanations.
  String get label => switch (this) {
    ClassificationSource.memory => 'personal_memory',
    ClassificationSource.exact => 'exact_rule',
    ClassificationSource.history => 'statistical_rule',
    ClassificationSource.catalog => 'merchant_rule',
    ClassificationSource.model => 'ml_model',
    ClassificationSource.fallback => 'fallback',
    ClassificationSource.none => 'none',
  };
}

class CategoryScore {
  const CategoryScore(
    this.categoryId,
    this.confidence,
    this.source, {
    this.evidence = 0,
  });
  final String categoryId;

  /// 0–1.
  final double confidence;
  final ClassificationSource source;

  /// How many past operations or choices it rests on (for explanations).
  final int evidence;
}

/// What to do with a classification, by the thresholds in [AiConfig] and
/// the person's automation level.
enum CategoryDecision { apply, suggest, choose, none }

/// Thresholds of the AI, in one place.
abstract final class AiConfig {
  /// At or above: may be applied without asking (when allowed).
  static const autoApply = .7;

  /// At or above: offered as the suggestion; below: top three to choose.
  static const suggest = .5;

  /// Below this the classifier says «not sure».
  static const minConfidence = .45;

  static CategoryDecision decide(ClassificationResult r, AiAutomation level) {
    if (r.top.isEmpty) return CategoryDecision.none;
    final c = r.top.first.confidence;
    return switch (level) {
      AiAutomation.suggestOnly =>
        c >= suggest ? CategoryDecision.suggest : CategoryDecision.choose,
      AiAutomation.smart =>
        c >= autoApply
            ? CategoryDecision.apply
            : c >= suggest
            ? CategoryDecision.suggest
            : CategoryDecision.choose,
      AiAutomation.automatic =>
        c >= suggest ? CategoryDecision.apply : CategoryDecision.choose,
    };
  }
}

class ClassificationResult {
  const ClassificationResult({
    required this.top,
    this.insufficient,
    this.modelVersion,
  });

  /// Up to three categories, best first.
  final List<CategoryScore> top;
  final Insufficient? insufficient;
  final String? modelVersion;

  CategoryScore? get best =>
      insufficient == null && top.isNotEmpty ? top.first : null;
}

/// One category's change between two periods.
class CategoryChange {
  const CategoryChange({
    required this.categoryId,
    required this.current,
    required this.previous,
  });
  final String categoryId;
  final int current, previous;
  int get difference => current - previous;

  /// Null when there was nothing in the previous period.
  double? get percent => previous == 0 ? null : difference / previous * 100;
}

class MonthComparison {
  const MonthComparison({
    required this.current,
    required this.previous,
    required this.drivers,
    required this.decreases,
    required this.comparableDays,
    this.insufficient,
  });

  /// Spending this period up to today and in the same days of the previous
  /// period (a fair comparison mid-month).
  final int current, previous;
  final int comparableDays;

  /// Categories that grew the most, biggest first.
  final List<CategoryChange> drivers;

  /// Categories that fell the most.
  final List<CategoryChange> decreases;
  final Insufficient? insufficient;

  int get difference => current - previous;
  double? get percent => previous == 0 ? null : difference / previous * 100;
}

enum Cadence { weekly, biweekly, monthly, quarterly, yearly }

/// A payment that repeats at a steady rhythm.
class RecurringCandidate {
  const RecurringCandidate({
    required this.merchantKey,
    required this.displayName,
    required this.cadence,
    required this.typicalAmount,
    required this.occurrences,
    required this.lastDate,
    required this.nextExpected,
    required this.confidence,
    required this.subscriptionLikely,
    required this.tracked,
    this.categoryId,
    this.serviceId,
    this.kind = EntryKind.expense,
    int? lastAmount,
  }) : lastAmount = lastAmount ?? typicalAmount;
  final String merchantKey, displayName;
  final Cadence cadence;
  final int typicalAmount, occurrences;
  final DateTime lastDate, nextExpected;
  final double confidence;

  /// A known subscription service, or a steady monthly amount.
  final bool subscriptionLikely;

  /// Already a regular payment in the app.
  final bool tracked;
  final String? categoryId, serviceId;

  /// An expense, or a regular income (salary, rent received).
  final EntryKind kind;

  /// The latest payment's amount.
  final int lastAmount;

  /// The latest payment differs from the usual one (by 5% and 10 ₽): a
  /// subscription going from 169 to 199 ₽ counts.
  bool get amountChanged =>
      (lastAmount - typicalAmount).abs() >= 1000 &&
      (lastAmount - typicalAmount).abs() >= typicalAmount * .05;

  /// Days of slack before a payment counts as «usually already happened».
  int get graceDays => switch (cadence) {
    Cadence.weekly => 2,
    Cadence.biweekly => 3,
    Cadence.monthly => 5,
    Cadence.quarterly => 10,
    Cadence.yearly => 20,
  };

  /// It usually would have happened by [now] and has not.
  bool isLate(DateTime now) =>
      now.isAfter(nextExpected.add(Duration(days: graceDays)));
}

/// What an unusual expense was compared with.
enum AnomalyBasis { category, merchant }

/// An unusually large expense.
class Anomaly {
  const Anomaly({
    required this.entry,
    required this.typical,
    required this.ratio,
    required this.firstAtMerchant,
    this.basis = AnomalyBasis.category,
    this.history = 0,
  });
  final FinanceEntry entry;

  /// The usual size of such an expense (median in its category).
  final int typical;
  final double ratio;
  final bool firstAtMerchant;

  /// Compared with the same place's past payments, or the category's.
  final AnomalyBasis basis;

  /// How many past expenses the norm rests on.
  final int history;
}

/// Spending forecast for the current period.
class Forecast {
  const Forecast({
    required this.spentSoFar,
    required this.projectedExpense,
    required this.incomeSoFar,
    required this.projectedIncome,
    required this.currentBalance,
    required this.projectedBalance,
    required this.upcomingMandatory,
    required this.daysLeft,
    this.insufficient,
    this.confidence = 0,
  });
  final int spentSoFar, projectedExpense, incomeSoFar, projectedIncome;
  final int currentBalance, projectedBalance, upcomingMandatory, daysLeft;
  final Insufficient? insufficient;

  /// 0–1: how far the forecast can be trusted (history and progress of the
  /// period); 0 when there is no forecast.
  final double confidence;
}

/// What is left after obligations.
class Cashflow {
  const Cashflow({
    required this.balance,
    required this.mandatory,
    required this.expectedVariable,
    required this.expectedIncome,
    required this.payments,
  });

  /// Money on the accounts that count in the total.
  final int balance;

  /// Regular payments still due this period.
  final int mandatory;

  /// Expected everyday spending for the rest of the period.
  final int expectedVariable;

  /// Regular incomes still due this period.
  final int expectedIncome;
  final List<RecurringRule> payments;

  int get afterMandatory => balance + expectedIncome - mandatory;
  int get afterAll => afterMandatory - expectedVariable;
}

class BudgetRisk {
  const BudgetRisk({
    required this.budget,
    required this.spent,
    required this.projected,
    required this.probability,
  });
  final Budget budget;
  final int spent, projected;

  /// 0–1: chance the budget is exceeded by the end of the period.
  final double probability;
  int get overrun => projected - budget.limitMinor;
}

enum Trend { rising, falling }

class CategoryTrend {
  const CategoryTrend(this.categoryId, this.trend, this.months);
  final String categoryId;
  final Trend trend;

  /// Monthly totals, oldest first.
  final List<int> months;
}

enum IncomeStability { stable, moderate, volatile }

class Habits {
  const Habits({
    this.busiestWeekday,
    this.weekdayShare = 0,
    this.averageExpense = 0,
    this.topMerchants = const [],
  });

  /// 1 = Monday … 7 = Sunday.
  final int? busiestWeekday;
  final double weekdayShare;
  final int averageExpense;
  final List<(String, int)> topMerchants;
}

class UnusualMonth {
  const UnusualMonth(this.month, this.total, this.average);
  final DateTime month;
  final int total, average;
}

class Patterns {
  const Patterns({
    required this.trends,
    required this.habits,
    required this.unusualMonths,
    this.incomeStability,
    this.seasonal = const [],
  });
  final List<CategoryTrend> trends;
  final Habits habits;
  final List<UnusualMonth> unusualMonths;
  final IncomeStability? incomeStability;

  /// Categories that a year ago, in the same month, were notably higher.
  final List<CategoryChange> seasonal;
}

class BudgetSuggestion {
  const BudgetSuggestion(this.categoryId, this.limit, this.basedOnMonths);
  final String categoryId;
  final int limit, basedOnMonths;
}

enum InsightKind {
  summary,
  growth,
  decrease,
  forecast,
  freeMoney,
  subscription,
  recurring,
  anomaly,
  budgetRisk,
  trend,
  incomeStability,
  habit,
  unusualMonth,
  suggestion,
  goal,

  /// A regular payment that usually would have happened by now.
  latePayment,

  /// Many more operations than usual by this day of the period.
  frequency,
  notEnoughData,
}

/// One fact worth telling, with the numbers it rests on, how sure Finora
/// is and where it came from.
class Insight {
  const Insight({
    required this.kind,
    required this.priority,
    this.categoryId,
    this.amount,
    this.secondAmount,
    this.percent,
    this.subject,
    this.recurring,
    this.anomaly,
    this.risk,
    this.trend,
    this.confidence = 1,
    InsightSeverity? severity,
    this.trace,
  }) : _severity = severity;
  final InsightKind kind;

  /// Higher shows first (before confidence is taken into account).
  final int priority;
  final String? categoryId, subject;
  final int? amount, secondAmount;
  final double? percent;
  final RecurringCandidate? recurring;
  final Anomaly? anomaly;
  final BudgetRisk? risk;
  final CategoryTrend? trend;

  /// 0–1.
  final double confidence;
  final InsightSeverity? _severity;

  /// Source, reason, input period and related operations.
  final InsightTrace? trace;

  InsightSeverity get severity =>
      _severity ??
      switch (kind) {
        InsightKind.budgetRisk ||
        InsightKind.anomaly ||
        InsightKind.latePayment => InsightSeverity.warning,
        InsightKind.growth ||
        InsightKind.subscription ||
        InsightKind.frequency ||
        InsightKind.unusualMonth => InsightSeverity.notice,
        InsightKind.decrease => InsightSeverity.positive,
        InsightKind.freeMoney when (amount ?? 0) < 0 => InsightSeverity.warning,
        _ => InsightSeverity.info,
      };

  /// The same fact about the same thing: shown once, snoozed together.
  String get dedupKey =>
      '${kind.name}:${categoryId ?? recurring?.merchantKey ?? subject ?? ''}';

  /// A stable id within the period of the data it rests on.
  String get id {
    final start = trace?.periodStart;
    return start == null
        ? dedupKey
        : '$dedupKey@${start.year}-${start.month}-${start.day}';
  }

  /// Ranking score: priority weighed by confidence, warnings first among
  /// equals.
  double get relevance =>
      priority * (.5 + .5 * confidence) +
      (severity == InsightSeverity.warning ? 4 : 0);
}
