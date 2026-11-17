import '../../../domain/models.dart';
import 'ai_models.dart' show RecurringCandidate;

/// Phase 1 structured results: traceability of insights, comparisons of
/// any two periods, the cash-flow timeline and frequency anomalies. Like the
/// rest of the AI models, every number here comes from an engine.

/// How a result should be read: a plain fact, good news, something worth
/// a look, or a warning.
enum InsightSeverity { info, positive, notice, warning }

/// Where an insight came from, so it can be checked: the engine, a short
/// machine-readable reason, the period of the input data, the operations it
/// rests on and the version of the calculation.
class InsightTrace {
  const InsightTrace({
    required this.sourceEngine,
    required this.reason,
    this.periodStart,
    this.periodEnd,
    this.relatedEntryIds = const [],
    this.calculationVersion = InsightTrace.version,
    this.generatedAt,
  });

  /// Bumped when an engine's arithmetic changes.
  static const version = 2;

  final String sourceEngine;

  /// E.g. «median of 6 past expenses in the category», as data:
  /// `category-median:6`, `merchant-median:4`, `pace-blend:3`.
  final String reason;
  final DateTime? periodStart, periodEnd;
  final List<String> relatedEntryIds;
  final int calculationVersion;
  final DateTime? generatedAt;
}

/// A calendar unit for comparisons.
enum PeriodUnit { day, week, month, quarter, year }

/// Two periods side by side: the current one up to today and the same
/// stretch of the previous one (or two custom ranges of equal length).
class PeriodComparison {
  const PeriodComparison({
    required this.unit,
    required this.currentStart,
    required this.currentEnd,
    required this.previousStart,
    required this.previousEnd,
    required this.expense,
    required this.previousExpense,
    required this.income,
    required this.previousIncome,
    required this.increases,
    required this.decreases,
    this.insufficient,
  });

  /// Null for a custom range.
  final PeriodUnit? unit;
  final DateTime currentStart, currentEnd, previousStart, previousEnd;
  final int expense, previousExpense, income, previousIncome;

  /// Categories that grew / fell the most (biggest change first).
  final List<CategoryDelta> increases, decreases;
  final InsufficientData? insufficient;

  int get expenseDifference => expense - previousExpense;
  int get incomeDifference => income - previousIncome;
  int get cashflow => income - expense;
  int get previousCashflow => previousIncome - previousExpense;
  int get cashflowDifference => cashflow - previousCashflow;

  double? get expensePercent =>
      previousExpense == 0 ? null : expenseDifference / previousExpense * 100;
  double? get incomePercent =>
      previousIncome == 0 ? null : incomeDifference / previousIncome * 100;
}

/// One category's change between two periods (same shape as the month
/// comparison's, kept separate so this file has no cycle).
class CategoryDelta {
  const CategoryDelta(this.categoryId, this.current, this.previous);
  final String categoryId;
  final int current, previous;
  int get difference => current - previous;
  double? get percent => previous == 0 ? null : difference / previous * 100;
}

/// Why a comparison could not be made honestly.
enum InsufficientData { noPreviousData, tooFewEntries }

/// What a cash-flow event is.
enum CashflowEventType { mandatory, subscription, recurring, income }

/// A money movement expected on a date: a regular payment of the app, or
/// one Finora detected from the history.
class CashflowEvent {
  const CashflowEvent({
    required this.date,
    required this.amount,
    required this.kind,
    required this.type,
    required this.title,
    required this.confidence,
    required this.detected,
    this.categoryId,
    this.late = false,
  });
  final DateTime date;
  final int amount;
  final EntryKind kind;
  final CashflowEventType type;
  final String title;

  /// 1 for the app's own regular payments; the detector's for found ones.
  final double confidence;

  /// Found in the history rather than set up in the app.
  final bool detected;
  final String? categoryId;

  /// Usually would have happened already by today (never «forgot to pay»).
  final bool late;

  int get signed => kind == EntryKind.income ? amount : -amount;
}

/// The rest of the period day by day: events and the projected balance.
class CashflowTimeline {
  const CashflowTimeline({
    required this.events,
    required this.balances,
    required this.late,
  });

  /// Expected events from today to the end of the period, by date.
  final List<CashflowEvent> events;

  /// Projected balance at the end of each day (events and the everyday
  /// pace); empty when there is no pace to project with.
  final List<(DateTime, int)> balances;

  /// Regular payments that usually would have happened by now.
  final List<CashflowEvent> late;

  /// The lowest projected balance and its day.
  (DateTime, int)? get lowest =>
      balances.isEmpty ? null : balances.reduce((a, b) => b.$2 < a.$2 ? b : a);
}

/// Many more operations than usual by this day of the period.
class FrequencyAnomaly {
  const FrequencyAnomaly({required this.count, required this.typical});
  final int count, typical;
}

/// What a regular payment is. Only [subscription] counts as a subscription;
/// rent, loans, utilities and transfers repeat too but are obligations.
enum PaymentNature { subscription, rent, loan, utilities, transfer, other }

/// A dream's outlook at the current saving pace.
class GoalForecast {
  const GoalForecast({
    required this.goal,
    required this.saved,
    required this.left,
    required this.monthlyPace,
    this.monthlyNeed,
    this.expectedDate,
  });
  final Goal goal;
  final int saved, left;

  /// Average monthly saving into it over the last three months.
  final int monthlyPace;

  /// What is needed a month to make the deadline (null without one).
  final int? monthlyNeed;

  /// When it is reached at the current pace (null: no pace yet).
  final DateTime? expectedDate;

  /// About a week's share of the monthly need.
  int? get weeklyNeed =>
      monthlyNeed == null ? null : (monthlyNeed! * 12 / 52 / 100).ceil() * 100;

  /// Ahead (positive) or behind (negative) the needed monthly saving.
  int? get deviation => monthlyNeed == null ? null : monthlyPace - monthlyNeed!;

  bool get done => left <= 0;
}

/// Subscriptions at a glance: what they cost, what is new, what changed and
/// what stopped.
class SubscriptionAnalytics {
  const SubscriptionAnalytics({
    required this.monthly,
    required this.count,
    required this.added,
    required this.priceChanged,
    required this.stopped,
  });

  /// Cost of all subscriptions a month (tracked ones and confirmed found
  /// ones), in minor units.
  final int monthly;
  final int count;
  int get yearly => monthly * 12;

  /// First seen within the last 45 days.
  final List<RecurringCandidate> added;

  /// The latest payment differs from the usual.
  final List<RecurringCandidate> priceChanged;

  /// Used to repeat, silent now.
  final List<RecurringCandidate> stopped;
}

/// How many months the savings would cover.
class Cushion {
  const Cushion({
    required this.savings,
    required this.monthlyExpenses,
    required this.monthlyMandatory,
  });

  /// Savings and deposit accounts, base currency.
  final int savings;

  /// Typical monthly spending (median of recent full months).
  final int monthlyExpenses;

  /// Regular obligations a month.
  final int monthlyMandatory;

  double? get months => monthlyExpenses <= 0 ? null : savings / monthlyExpenses;
  double? get mandatoryMonths =>
      monthlyMandatory <= 0 ? null : savings / monthlyMandatory;
}

/// One part of the stability index and why it scored so.
class StabilityFactor {
  const StabilityFactor(this.name, this.points, this.max, this.reason);
  final String name, reason;
  final int points, max;
}

/// Finora's stability index (0–100) — not a credit score: how steady the
/// money is, with the reasons, so a change can be understood.
class StabilityScore {
  const StabilityScore(this.factors);
  final List<StabilityFactor> factors;
  int get score => factors.fold(0, (a, f) => a + f.points);
  int get max => factors.fold(0, (a, f) => a + f.max);
}
