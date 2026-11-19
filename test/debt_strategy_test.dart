import 'package:finora/domain/debt_strategy.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/features/finora_ai/insights/debt_advice.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_test/flutter_test.dart';

/// Paying debts off: avalanche, snowball and minimums only, in kopecks.
void main() {
  const card = DebtItem(
    id: 'card',
    name: 'Кредитка',
    balanceMinor: 6000000, // 60 000 ₽
    annualRate: 30,
    minimumMinor: 300000,
  );
  const loan = DebtItem(
    id: 'loan',
    name: 'Кредит',
    balanceMinor: 20000000, // 200 000 ₽
    annualRate: 15,
    minimumMinor: 700000,
  );
  const friend = DebtItem(
    id: 'friend',
    name: 'Саше',
    balanceMinor: 1000000, // 10 000 ₽
    annualRate: 0,
    minimumMinor: 0,
  );

  test('one debt without interest closes on schedule', () {
    final p = DebtStrategies.simulate(const [
      DebtItem(
        id: 'a',
        name: 'Рассрочка',
        balanceMinor: 1200000,
        annualRate: 0,
        minimumMinor: 100000,
      ),
    ]);
    expect(p.finished, isTrue);
    expect(p.months, 12);
    expect(p.totalInterestMinor, 0);
    expect(p.totalPaidMinor, 1200000);
  });

  test('interest is charged monthly in whole kopecks', () {
    final p = DebtStrategies.simulate(const [
      DebtItem(
        id: 'a',
        name: 'Кредит',
        balanceMinor: 1200000,
        annualRate: 12,
        minimumMinor: 1300000,
      ),
    ]);
    // 12 000 ₽ × 1 % = 120 ₽ in the first month, then closed.
    expect(p.months, 1);
    expect(p.totalInterestMinor, 12000);
    expect(p.totalPaidMinor, 1212000);
  });

  test('avalanche pays less interest; snowball closes the small one first', () {
    final debts = [card, loan, friend];
    final plans = DebtStrategies.compare(debts, 500000);
    final avalanche = plans.firstWhere(
      (p) => p.strategy == DebtStrategy.avalanche,
    );
    final snowball = plans.firstWhere(
      (p) => p.strategy == DebtStrategy.snowball,
    );
    final base = plans.last;
    expect(base.strategy, isNull);
    expect(avalanche.finished, isTrue);
    expect(snowball.finished, isTrue);
    // The person owing a friend with no schedule never closes on minimums.
    expect(base.finished, isFalse);
    expect(
      avalanche.totalInterestMinor,
      lessThanOrEqualTo(snowball.totalInterestMinor),
    );
    expect(snowball.order.first, 'friend');
    expect(avalanche.order.first, 'card');
    // Recommended first.
    expect(plans.first.strategy, DebtStrategy.avalanche);
    // Same money each month until the end (minimums + extra).
    for (final m in avalanche.schedule.take(5)) {
      expect(m.totalMinor, 300000 + 700000 + 500000);
    }
  });

  test('more money each month closes sooner and costs less', () {
    final little = DebtStrategies.simulate([card, loan], extraMinor: 100000);
    final more = DebtStrategies.simulate([card, loan], extraMinor: 1000000);
    final none = DebtStrategies.simulate([card, loan], strategy: null);
    expect(more.months, lessThan(little.months));
    expect(more.totalInterestMinor, lessThan(little.totalInterestMinor));
    expect(little.totalInterestMinor, lessThan(none.totalInterestMinor));
  });

  test('a payment below the interest never finishes', () {
    final p = DebtStrategies.simulate(const [
      DebtItem(
        id: 'a',
        name: 'Микрозайм',
        balanceMinor: 10000000,
        annualRate: 120,
        minimumMinor: 50000,
      ),
    ]);
    expect(p.finished, isFalse);
  });

  test('debts and free money come from the person data', () async {
    final now = DateTime(2026, 11, 19);
    final data = FinanceData(
      accounts: const [Account(id: 'card', name: 'Карта')],
      categories: const [
        Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
        Category(id: 'loans', name: 'Кредиты', kind: EntryKind.expense),
        Category(id: 'pay', name: 'Зарплата', kind: EntryKind.income),
      ],
      recurring: [
        RecurringRule(
          id: 'r1',
          name: 'Рассрочка телефона',
          accountId: 'card',
          categoryId: 'loans',
          amountMinor: 500000,
          totalMinor: 3000000,
          nextDate: DateTime(2026, 12, 5),
        ),
      ],
      entries: [
        for (var m = 8; m <= 10; m++) ...[
          FinanceEntry(
            id: 'in$m',
            kind: EntryKind.income,
            amountMinor: 10000000,
            currency: 'RUB',
            accountId: 'card',
            categoryId: 'pay',
            date: DateTime(2026, m, 10),
          ),
          FinanceEntry(
            id: 'out$m',
            kind: EntryKind.expense,
            amountMinor: 6000000,
            currency: 'RUB',
            accountId: 'card',
            categoryId: 'food',
            date: DateTime(2026, m, 15),
          ),
        ],
      ],
    );
    final debts = DebtStrategies.debtsOf(data, currency: 'RUB', now: now);
    expect(debts.single.balanceMinor, 3000000);
    expect(debts.single.minimumMinor, 500000);
    final cap = DebtStrategies.capacity(data, currency: 'RUB', now: now);
    expect(cap.months, 3);
    expect(cap.incomeMinor, 10000000);
    expect(cap.spendingMinor, 6000000);
    expect(cap.freeMinor, 10000000 - 6000000 - 500000);
    expect(cap.suggestedExtraMinor, 1750000);
    expect(DebtStrategies.monthly(100000, 'weekly', 1), 435000);
    // Finora AI answers from the same numbers.
    await initializeDateFormatting('ru');
    expect(DebtAdvice.matches('как мне быстрее погасить долги?'), isTrue);
    expect(DebtAdvice.matches('когда я закрою кредит'), isTrue);
    expect(
      DebtAdvice.matches('запланируй платежи по долгам на неделю'),
      isFalse,
    );
    expect(DebtAdvice.matches('сколько я потратил'), isFalse);
    final text = DebtAdvice.answer(data, currency: 'RUB', now: now);
    expect(text, contains('Рассрочка телефона'));
    expect(text, contains(RegExp(r'17\s500')));
    expect(text, contains('«Долги»'));
    final empty = DebtAdvice.answer(
      const FinanceData(),
      currency: 'RUB',
      now: now,
    );
    expect(empty, contains('нет долгов'));
  });
}
