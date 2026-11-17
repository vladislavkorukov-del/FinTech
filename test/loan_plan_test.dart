import 'package:finora/domain/models.dart';
import 'package:finora/domain/payment_plan.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loans and mortgages with a rate: the schedule is calculated the bank's
/// way — daily interest, the payment covers interest first, the last one is
/// smaller — and recorded payments (early ones too) lower the debt.
void main() {
  final today = DateTime(2026, 11, 17);
  RecurringRule loan({
    int debt = 12000000,
    double rate = 12,
    int payment = 1070000,
    int? total,
  }) => RecurringRule(
    id: 'car',
    name: 'Автокредит',
    accountId: 'card',
    currency: 'RUB',
    kind: EntryKind.expense,
    amountMinor: payment,
    interval: 1,
    frequency: 'monthly',
    paymentType: 'mandatory',
    nextDate: DateTime(2026, 12, 17),
    anchorDay: 17,
    interestRate: rate,
    principalMinor: debt,
    principalDate: today,
    totalMinor: total,
  );

  FinanceEntry paid(DateTime d, int minor, [int n = 0]) => FinanceEntry(
    id: 'recurring:car:$n',
    kind: EntryKind.expense,
    amountMinor: minor,
    currency: 'RUB',
    accountId: 'card',
    date: d,
  );

  test('the annuity formula: 120 000 at 12% for 12 months', () {
    // 10 661,85 ₽ — rounded up to whole rubles.
    expect(PaymentPlan.annuity(12000000, 12, 12), 1066200);
    expect(PaymentPlan.annuity(12000000, 0, 12), 1000000);
  });

  test('the schedule repays the debt with interest, last one smaller', () {
    final plan = PaymentPlan.of(loan(), const [], now: today);
    final l = plan.loan!;
    expect(l.repayable, isTrue);
    expect(l.debtMinor, 12000000);
    expect(plan.upcoming.length, 12);
    expect(plan.upcoming.last.debtAfterMinor, 0);
    expect(
      plan.upcoming.last.amountMinor,
      lessThan(plan.upcoming.first.amountMinor),
    );
    // Every payment: interest + debt part = payment.
    for (final p in plan.upcoming) {
      expect(p.interestMinor! + p.principalMinor!, closeTo(p.amountMinor, 1));
    }
    // First month: 120 000 × 12% × 30/365 ≈ 1 183,56 ₽.
    expect(plan.upcoming.first.interestMinor, closeTo(118356, 2));
    // Interest falls as the debt does.
    expect(
      plan.upcoming[5].interestMinor,
      lessThan(plan.upcoming.first.interestMinor!),
    );
    // About 7 900 ₽ of interest over the year: an annuity at 12% pays
    // 12 × 10 661,85 − 120 000 ≈ 7 942 ₽; the payment here is a bit higher.
    expect(l.interestAheadMinor, inInclusiveRange(770000, 800000));
    expect(l.leftToPayMinor, l.debtMinor + l.interestAheadMinor);
    expect(l.payoffDate, plan.upcoming.last.date);
    expect(plan.progress, 0);
    expect(plan.hasTotal, isTrue);
    expect(plan.upcoming.first.of, 12);
  });

  test('an early payment lowers the debt and shortens the schedule', () {
    final before = PaymentPlan.of(loan(), const [], now: today);
    final after = PaymentPlan.of(loan(), [
      paid(DateTime(2026, 11, 27), 3000000),
    ], now: DateTime(2026, 11, 28));
    // 30 000 minus ten days of interest went to the debt.
    expect(after.loan!.debtMinor, inInclusiveRange(9030000, 9040000));
    expect(after.upcoming.length, lessThan(before.upcoming.length));
    expect(
      after.loan!.interestAheadMinor,
      lessThan(before.loan!.interestAheadMinor),
    );
    expect(after.progress, greaterThan(0));
    expect(after.paidCount, 1);
  });

  test('a payment below the interest is reported, not looped forever', () {
    final plan = PaymentPlan.of(
      loan(debt: 1000000000, rate: 20, payment: 1000000),
      const [],
      now: today,
    );
    expect(plan.loan!.repayable, isFalse);
    expect(plan.loan!.payoffDate, isNull);
    expect(plan.upcoming.length, lessThan(10));
  });

  test('a loan survives a save', () {
    final r = loan();
    final back = RecurringRule.fromJson(r.toJson());
    expect(back.interestRate, 12);
    expect(back.principalMinor, 12000000);
    expect(back.principalDate, today);
    expect(back.isLoan, isTrue);
    // A plain payment is not a loan.
    expect(back.copyWith(interestRate: null).isLoan, isFalse);
  });
}
