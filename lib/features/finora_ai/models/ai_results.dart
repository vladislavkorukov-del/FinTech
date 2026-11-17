import '../../../domain/models.dart';

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
