import '../../../domain/finance_engine.dart';
import '../../../domain/models.dart';
import '../../../domain/payee_summary.dart';

/// The data every engine works from, prepared once: posted operations in
/// the base currency, the current period and per-month slices.
///
/// Operations in other currencies are left out of the analysis (amounts in
/// different currencies cannot be added honestly without a rate).
class AiContext {
  AiContext(this.data, {DateTime? now, DateTime? periodStart})
    : now = now ?? DateTime.now(),
      currency = data.preferences.baseCurrency {
    final start = periodStart ?? _periodStart(data, this.now);
    this.periodStart = start;
    periodEnd = DateTime(start.year, start.month + 1, start.day);
    posted =
        data.entries
            .where((e) => e.status == 'posted' && e.currency == currency)
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    expenses = posted.where((e) => e.kind == EntryKind.expense).toList();
    incomes = posted.where((e) => e.kind == EntryKind.income).toList();
  }

  final FinanceData data;
  final DateTime now;
  final String currency;
  late final DateTime periodStart, periodEnd;
  late final List<FinanceEntry> posted, expenses, incomes;

  static DateTime _periodStart(FinanceData data, DateTime now) {
    final day = data.preferences.monthStart.clamp(1, 28);
    final start = DateTime(now.year, now.month, day);
    return now.isBefore(start) ? DateTime(now.year, now.month - 1, day) : start;
  }

  /// The period that started [back] periods before the current one.
  (DateTime, DateTime) period(int back) {
    final s = DateTime(
      periodStart.year,
      periodStart.month - back,
      periodStart.day,
    );
    return (s, DateTime(s.year, s.month + 1, s.day));
  }

  static bool inRange(FinanceEntry e, DateTime start, DateTime end) =>
      !e.date.isBefore(start) && e.date.isBefore(end);

  int sum(Iterable<FinanceEntry> list) =>
      list.fold(0, (a, e) => a + e.amountMinor);

  List<FinanceEntry> expensesIn(DateTime start, DateTime end) =>
      expenses.where((e) => inRange(e, start, end)).toList();

  List<FinanceEntry> incomesIn(DateTime start, DateTime end) =>
      incomes.where((e) => inRange(e, start, end)).toList();

  Map<String, int> byCategory(Iterable<FinanceEntry> list) {
    final out = <String, int>{};
    for (final e in list) {
      final id = e.categoryId ?? '';
      out[id] = (out[id] ?? 0) + e.amountMinor;
    }
    return out;
  }

  /// Days of the current period passed, today included.
  int get daysPassed =>
      DateTime(now.year, now.month, now.day).difference(periodStart).inDays + 1;

  int get periodDays => periodEnd.difference(periodStart).inDays;
  int get daysLeft => (periodDays - daysPassed).clamp(0, periodDays);

  /// Full periods back with at least one expense (most recent first).
  List<int> get fullPeriodsWithData => [
    for (var back = 1; back <= 12; back++)
      if (expensesIn(period(back).$1, period(back).$2).isNotEmpty) back,
  ];

  /// Total of the accounts that count in the balance, base currency.
  int get balance =>
      FinanceEngine.totalBalance(data.accounts, data.entries, currency);

  String categoryName(String? id) =>
      data.categories.where((c) => c.id == id).firstOrNull?.name ?? 'Прочее';

  static String merchantKey(String payee) => PayeeSummary.key(payee);
}

/// Median of a non-empty list.
double median(List<num> values) {
  final s = [...values]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m].toDouble() : (s[m - 1] + s[m]) / 2;
}
