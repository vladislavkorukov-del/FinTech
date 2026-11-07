import 'finance_engine.dart';
import 'models.dart';

/// One payment of a plan: «платёж 7 из 12», its date and sum.
class PlannedPayment {
  const PlannedPayment({
    required this.number,
    required this.of,
    required this.date,
    required this.amountMinor,
    required this.overdue,
  });
  final int number, of;
  final DateTime date;
  final int amountMinor;
  final bool overdue;
}

/// Where a payment stands (Finora 1.36): what is paid, what is left, the
/// payments still ahead (for a loan or instalment plan with a whole sum),
/// and whether the current one is late.
class PaymentPlan {
  PaymentPlan._({
    required this.rule,
    required this.paidMinor,
    required this.paidCount,
    required this.upcoming,
    required this.overdueDays,
  });

  final RecurringRule rule;
  final int paidMinor, paidCount;
  final List<PlannedPayment> upcoming;

  /// Days since the unpaid date; 0 — not late.
  final int overdueDays;

  bool get hasTotal => rule.totalMinor != null;
  int get leftMinor =>
      hasTotal ? (rule.totalMinor! - paidMinor).clamp(0, rule.totalMinor!) : 0;
  bool get done => hasTotal && leftMinor == 0;
  bool get overdue => overdueDays > 0;
  int get totalCount => paidCount + upcoming.length;
  double get progress =>
      hasTotal && rule.totalMinor! > 0 ? paidMinor / rule.totalMinor! : 0;

  /// Operations recorded for [rule]: `recurring:<id>:…`.
  static bool belongs(FinanceEntry e, RecurringRule rule) =>
      e.id.startsWith('recurring:${rule.id}:') && e.status != 'cancelled';

  static PaymentPlan of(
    RecurringRule rule,
    List<FinanceEntry> entries, {
    DateTime? now,
    int horizon = 120,
  }) {
    final clock = now ?? DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day);
    final mine = entries.where((e) => belongs(e, rule)).toList();
    final paid = mine.fold(0, (sum, e) => sum + e.amountMinor);
    final due = DateTime(
      rule.nextDate.year,
      rule.nextDate.month,
      rule.nextDate.day,
    );
    final late = rule.enabled && due.isBefore(today)
        ? today.difference(due).inDays
        : 0;
    final upcoming = <PlannedPayment>[];
    if (rule.totalMinor != null) {
      var left = rule.totalMinor! - paid;
      var current = rule;
      while (left > 0 && upcoming.length < 600) {
        final sum = left < rule.amountMinor ? left : rule.amountMinor;
        final d = current.nextDate;
        upcoming.add(
          PlannedPayment(
            number: mine.length + upcoming.length + 1,
            of: 0,
            date: d,
            amountMinor: sum,
            overdue: DateTime(d.year, d.month, d.day).isBefore(today),
          ),
        );
        left -= sum;
        final next = FinanceEngine.nextOccurrence(current);
        if (!next.isAfter(current.nextDate)) break;
        current = current.copyWith(nextDate: next);
      }
    } else {
      var current = rule;
      for (var i = 0; i < horizon && i < 24; i++) {
        final d = current.nextDate;
        upcoming.add(
          PlannedPayment(
            number: mine.length + i + 1,
            of: 0,
            date: d,
            amountMinor: rule.amountMinor,
            overdue: DateTime(d.year, d.month, d.day).isBefore(today),
          ),
        );
        final next = FinanceEngine.nextOccurrence(current);
        if (!next.isAfter(current.nextDate)) break;
        current = current.copyWith(nextDate: next);
      }
    }
    final total = rule.totalMinor == null ? 0 : mine.length + upcoming.length;
    return PaymentPlan._(
      rule: rule,
      paidMinor: paid,
      paidCount: mine.length,
      overdueDays: late,
      upcoming: [
        for (final p in upcoming)
          PlannedPayment(
            number: p.number,
            of: total,
            date: p.date,
            amountMinor: p.amountMinor,
            overdue: p.overdue,
          ),
      ],
    );
  }
}
