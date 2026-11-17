import '../../../domain/models.dart';

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

/// Where a classification came from, most trusted first.
enum ClassificationSource { memory, history, catalog, model, none }

class CategoryScore {
  const CategoryScore(this.categoryId, this.confidence, this.source);
  final String categoryId;

  /// 0–1.
  final double confidence;
  final ClassificationSource source;
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

enum Cadence { weekly, monthly, yearly }

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
  });
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
}

/// An unusually large expense.
class Anomaly {
  const Anomaly({
    required this.entry,
    required this.typical,
    required this.ratio,
    required this.firstAtMerchant,
  });
  final FinanceEntry entry;

  /// The usual size of such an expense (median in its category).
  final int typical;
  final double ratio;
  final bool firstAtMerchant;
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
  });
  final int spentSoFar, projectedExpense, incomeSoFar, projectedIncome;
  final int currentBalance, projectedBalance, upcomingMandatory, daysLeft;
  final Insufficient? insufficient;
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
  notEnoughData,
}

/// One fact worth telling, with the numbers it rests on.
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
  });
  final InsightKind kind;

  /// Higher shows first.
  final int priority;
  final String? categoryId, subject;
  final int? amount, secondAmount;
  final double? percent;
  final RecurringCandidate? recurring;
  final Anomaly? anomaly;
  final BudgetRisk? risk;
  final CategoryTrend? trend;
}
