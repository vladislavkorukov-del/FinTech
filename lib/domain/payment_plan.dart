import 'dart:math' as math;

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
    this.interestMinor,
    this.principalMinor,
    this.debtAfterMinor,
  });
  final int number, of;
  final DateTime date;
  final int amountMinor;
  final bool overdue;

  /// For a loan with a rate: how much of the payment is interest and how
  /// much repays the debt, and the debt left after it.
  final int? interestMinor, principalMinor, debtAfterMinor;
}

/// A loan with interest at a glance: the debt left today, the interest
/// still ahead, everything left to pay and the date of the last payment.
class LoanSummary {
  const LoanSummary({
    required this.debtMinor,
    required this.startDebtMinor,
    required this.interestAheadMinor,
    required this.interestPaidMinor,
    required this.payoffDate,
    required this.repayable,
  });
  final int debtMinor, startDebtMinor, interestAheadMinor, interestPaidMinor;
  final DateTime? payoffDate;

  /// False when the payment does not even cover the interest.
  final bool repayable;
  int get leftToPayMinor => debtMinor + interestAheadMinor;
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
    this.loan,
  });

  final RecurringRule rule;
  final int paidMinor, paidCount;
  final List<PlannedPayment> upcoming;

  /// Days since the unpaid date; 0 — not late.
  final int overdueDays;

  /// Set for a loan with a rate (see [RecurringRule.isLoan]).
  final LoanSummary? loan;

  bool get hasTotal => rule.totalMinor != null || loan != null;

  /// What is left: the debt of a loan, or the rest of a whole sum.
  int get leftMinor => loan != null
      ? loan!.debtMinor
      : rule.totalMinor != null
      ? (rule.totalMinor! - paidMinor).clamp(0, rule.totalMinor!)
      : 0;
  bool get done => hasTotal && leftMinor == 0;
  bool get overdue => overdueDays > 0;
  int get totalCount => paidCount + upcoming.length;
  double get progress {
    final l = loan;
    if (l != null) {
      return l.startDebtMinor <= 0 ? 0 : 1 - l.debtMinor / l.startDebtMinor;
    }
    return rule.totalMinor != null && rule.totalMinor! > 0
        ? paidMinor / rule.totalMinor!
        : 0;
  }

  /// Interest for [days] on [debt] at [rate] percent a year (actual/365, as
  /// Russian banks count it).
  static double interest(double debt, double rate, int days) =>
      days <= 0 ? 0 : debt * rate / 100 * days / 365;

  /// The bank's way: interest accrues daily; each payment covers the
  /// interest due first, the rest lowers the debt. Recorded payments since
  /// [RecurringRule.principalDate] are replayed, then the regular payment is
  /// projected until the debt is gone (the last one smaller).
  static PaymentPlan _loan(
    RecurringRule rule,
    List<FinanceEntry> mine,
    DateTime today,
    int late,
  ) {
    final rate = rule.interestRate!;
    final start = rule.principalDate ?? today;
    var debt = rule.principalMinor!.toDouble();
    var accrued = 0.0, paidInterest = 0.0;
    var last = DateTime(start.year, start.month, start.day);
    var paid = 0;
    final counted = [
      for (final e in mine)
        if (!e.date.isBefore(last)) e,
    ]..sort((a, b) => a.date.compareTo(b.date));
    for (final e in counted) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      accrued += interest(debt, rate, d.difference(last).inDays);
      final toInterest = e.amountMinor < accrued
          ? e.amountMinor.toDouble()
          : accrued;
      accrued -= toInterest;
      paidInterest += toInterest;
      debt = (debt - (e.amountMinor - toInterest)).clamp(0, double.infinity);
      last = d;
      paid += e.amountMinor;
    }
    final debtNow = debt.round();
    final upcoming = <PlannedPayment>[];
    var ahead = 0.0;
    var repayable = true;
    var current = rule;
    while (debt >= 1 && upcoming.length < 600) {
      final d = DateTime(
        current.nextDate.year,
        current.nextDate.month,
        current.nextDate.day,
      );
      final from = d.isBefore(last) ? d : last;
      accrued += interest(debt, rate, d.difference(from).inDays);
      final due = debt + accrued;
      final pay = due < rule.amountMinor ? due : rule.amountMinor.toDouble();
      final toInterest = pay < accrued ? pay : accrued;
      if (pay - toInterest < 1 && upcoming.length > 2) {
        // The payment does not cover the interest: the debt never ends.
        repayable = false;
        break;
      }
      accrued -= toInterest;
      ahead += toInterest;
      debt -= pay - toInterest;
      if (debt < 1) debt = 0;
      upcoming.add(
        PlannedPayment(
          number: counted.length + upcoming.length + 1,
          of: 0,
          date: current.nextDate,
          amountMinor: pay.round(),
          overdue: d.isBefore(today),
          interestMinor: toInterest.round(),
          principalMinor: (pay - toInterest).round(),
          debtAfterMinor: debt.round(),
        ),
      );
      last = d;
      final next = FinanceEngine.nextOccurrence(current);
      if (!next.isAfter(current.nextDate)) break;
      current = current.copyWith(nextDate: next);
    }
    final total = counted.length + upcoming.length;
    return PaymentPlan._(
      rule: rule,
      paidMinor: paid,
      paidCount: counted.length,
      overdueDays: late,
      loan: LoanSummary(
        debtMinor: debtNow,
        startDebtMinor: rule.principalMinor!,
        interestAheadMinor: repayable ? ahead.round() : 0,
        interestPaidMinor: paidInterest.round(),
        payoffDate: repayable && upcoming.isNotEmpty
            ? upcoming.last.date
            : null,
        repayable: repayable,
      ),
      upcoming: [
        for (final p in upcoming)
          PlannedPayment(
            number: p.number,
            of: repayable ? total : 0,
            date: p.date,
            amountMinor: p.amountMinor,
            overdue: p.overdue,
            interestMinor: p.interestMinor,
            principalMinor: p.principalMinor,
            debtAfterMinor: p.debtAfterMinor,
          ),
      ],
    );
  }

  /// The regular payment that repays [debtMinor] at [rate] percent a year in
  /// [months] equal monthly payments (the annuity formula), in whole rubles.
  static int annuity(int debtMinor, double rate, int months) {
    if (months <= 0) return debtMinor;
    final i = rate / 100 / 12;
    if (i == 0) return (debtMinor / months / 100).ceil() * 100;
    final k = i * math.pow(1 + i, months) / (math.pow(1 + i, months) - 1);
    return (debtMinor * k / 100).ceil() * 100;
  }

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
    if (rule.isLoan) return _loan(rule, mine, today, late);
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
