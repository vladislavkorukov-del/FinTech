import 'package:flutter_test/flutter_test.dart';

import 'package:finora/domain/finance_engine.dart';
import 'package:finora/domain/models.dart';

void main() {
  final start = DateTime(2026, 11);
  final end = DateTime(2026, 12);
  const bank = Account(id: 'bank', name: 'Карта', openingMinor: 100000);
  const cash = Account(id: 'cash', name: 'Наличные', openingMinor: 10000);
  const usd = Account(id: 'usd', name: 'USD', currency: 'USD');
  const food = Category(id: 'food', name: 'Продукты', kind: EntryKind.expense);
  const salary = Category(
    id: 'salary',
    name: 'Зарплата',
    kind: EntryKind.income,
  );
  final data = const FinanceData(
    accounts: [bank, cash, usd],
    categories: [food, salary],
  );

  FinanceEntry entry({
    String id = 'entry',
    EntryKind kind = EntryKind.expense,
    int amount = 25000,
    String account = 'bank',
    String currency = 'RUB',
    String? destination,
    int? destinationMinor,
    String? category = 'food',
    String status = 'posted',
    DateTime? date,
  }) => FinanceEntry(
    id: id,
    kind: kind,
    amountMinor: amount,
    accountId: account,
    currency: currency,
    toAccountId: destination,
    destinationMinor: destinationMinor,
    categoryId: category,
    date: date ?? DateTime(2026, 11, 4),
    status: status,
  );

  group('Aggregate bounds', () {
    test('an overflowing account total is rejected instead of wrapping', () {
      final rows = List.generate(
        2048,
        (i) => entry(
          id: '$i',
          kind: EntryKind.income,
          category: 'salary',
          amount: FinanceEngine.maxMinor,
        ),
      );
      expect(() => FinanceEngine.balance(bank, rows), throwsFormatException);
      expect(
        () => FinanceEngine.totals(rows, start, end, 'RUB'),
        throwsFormatException,
      );
    });
    test(
      'balance arithmetic remains exact when large opposing flows cancel',
      () {
        final rows = [
          ...List.generate(
            2048,
            (i) => entry(
              id: 'i$i',
              kind: EntryKind.income,
              category: 'salary',
              amount: FinanceEngine.maxMinor,
            ),
          ),
          ...List.generate(
            2048,
            (i) => entry(id: 'e$i', amount: FinanceEngine.maxMinor),
          ),
        ];
        expect(FinanceEngine.balance(bank, rows), 100000);
      },
    );
    test(
      'combined active balance respects currency, archive and exclusion',
      () {
        final excluded = bank.copyWith(
          id: 'excluded',
          excluded: true,
          openingMinor: FinanceEngine.maxMinor,
        );
        expect(
          FinanceEngine.totalBalance([bank, cash, usd, excluded], [], 'RUB'),
          110000,
        );
        expect(
          () => FinanceEngine.totalBalance(
            [bank.copyWith(openingMinor: FinanceEngine.maxMinor), cash],
            [],
            'RUB',
          ),
          throwsFormatException,
        );
      },
    );
  });

  group('Exact monetary input', () {
    test('parses common Russian amount formats exactly', () {
      expect(FinanceEngine.parseMinor('1 234,56'), 123456);
      expect(FinanceEngine.parseMinor('12.3'), 1230);
      expect(FinanceEngine.parseMinor('12'), 1200);
      expect(FinanceEngine.parseMinor('0,01'), 1);
      expect(FinanceEngine.parseMinor('-7.45'), -745);
      expect(FinanceEngine.parseMinor('1\u00a0234,56'), 123456);
    });
    test('rejects excessive precision, malformed or exponential input', () {
      for (final value in [
        '',
        '.',
        '1e6',
        '12,345',
        '1.2.3',
        'NaN',
        'Infinity',
      ]) {
        expect(
          () => FinanceEngine.parseMinor(value),
          throwsFormatException,
          reason: value,
        );
      }
    });
    test('accepts exact cross-platform integer limit and rejects overflow', () {
      expect(
        FinanceEngine.parseMinor('90071992547409.91'),
        FinanceEngine.maxMinor,
      );
      expect(
        () => FinanceEngine.parseMinor('90071992547409.92'),
        throwsFormatException,
      );
    });
  });

  group('Account balances', () {
    test('uses opening balance plus posted incomes minus posted expenses', () {
      final entries = [
        entry(),
        entry(kind: EntryKind.income, amount: 50000, category: 'salary'),
        entry(amount: 99000, status: 'pending'),
        entry(amount: 99000, status: 'cancelled'),
      ];
      expect(FinanceEngine.balance(bank, entries), 125000);
      expect(FinanceEngine.balance(cash, entries), 10000);
    });
    test('allows negative balances for credit accounts', () {
      expect(FinanceEngine.balance(bank, [entry(amount: 150000)]), -50000);
    });
    test(
      'edits, deletes and restores entries without accumulating balance drift',
      () {
        final original = entry();
        expect(FinanceEngine.balance(bank, [original]), 75000);
        expect(
          FinanceEngine.balance(bank, [original.copyWith(amountMinor: 30000)]),
          70000,
        );
        expect(FinanceEngine.balance(bank, []), 100000);
        expect(FinanceEngine.balance(bank, [original]), 75000);
      },
    );
  });

  group('Transfers', () {
    final transfer = entry(
      kind: EntryKind.transfer,
      amount: 20000,
      destination: 'cash',
      category: null,
    );
    test('debits sender and credits recipient equally', () {
      FinanceEngine.validateEntry(transfer, data);
      expect(FinanceEngine.balance(bank, [transfer]), 80000);
      expect(FinanceEngine.balance(cash, [transfer]), 30000);
      expect(
        FinanceEngine.balance(bank, [transfer]) +
            FinanceEngine.balance(cash, [transfer]),
        110000,
      );
    });
    test('never counts a transfer as income or expense', () {
      expect(FinanceEngine.totals([transfer], start, end, 'RUB'), (
        income: 0,
        expense: 0,
        net: 0,
      ));
      expect(
        FinanceEngine.categoryTotals(
          [transfer],
          start,
          end,
          'RUB',
          EntryKind.transfer,
        ),
        isEmpty,
      );
    });
    test('pending transfers affect neither account', () {
      expect(
        FinanceEngine.balance(bank, [transfer.copyWith(status: 'pending')]),
        100000,
      );
      expect(
        FinanceEngine.balance(cash, [transfer.copyWith(status: 'pending')]),
        10000,
      );
    });
    test(
      'supports different destination currency using explicit received amount',
      () {
        final conversion = transfer.copyWith(
          toAccountId: 'usd',
          destinationMinor: 210,
        );
        FinanceEngine.validateEntry(conversion, data);
        expect(FinanceEngine.balance(bank, [conversion]), 80000);
        expect(FinanceEngine.balance(usd, [conversion]), 210);
      },
    );
    test('requires explicit received amount for cross-currency transfer', () {
      expect(
        () => FinanceEngine.validateEntry(
          transfer.copyWith(toAccountId: 'usd'),
          data,
        ),
        throwsFormatException,
      );
    });
    test('rejects same account and nonexistent recipient', () {
      for (final destination in ['bank', 'missing']) {
        expect(
          () => FinanceEngine.validateEntry(
            transfer.copyWith(toAccountId: destination),
            data,
          ),
          throwsFormatException,
        );
      }
    });
    test('rejects changing money in same-currency transfer', () {
      expect(
        () => FinanceEngine.validateEntry(
          transfer.copyWith(destinationMinor: 100),
          data,
        ),
        throwsFormatException,
      );
    });
    test('rejects expense category on transfer', () {
      expect(
        () => FinanceEngine.validateEntry(
          transfer.copyWith(categoryId: 'food'),
          data,
        ),
        throwsFormatException,
      );
    });
  });

  group('Budgets and statistics', () {
    final entries = [
      entry(amount: 25000),
      entry(amount: 10000, category: 'transport'),
      entry(kind: EntryKind.income, amount: 100000, category: 'salary'),
      entry(
        kind: EntryKind.transfer,
        amount: 10000,
        category: null,
        destination: 'cash',
      ),
      entry(amount: 99000, status: 'pending'),
      entry(amount: 99000, status: 'cancelled'),
      entry(amount: 99000, currency: 'USD', account: 'usd'),
      entry(amount: 99000, date: DateTime(2026, 10, 31, 23, 59)),
      entry(amount: 99000, date: DateTime(2026, 12)),
    ];
    test('counts only posted operations in selected currency and period', () {
      expect(FinanceEngine.totals(entries, start, end, 'RUB'), (
        income: 100000,
        expense: 35000,
        net: 65000,
      ));
    });
    test('period start is inclusive and end is exclusive', () {
      final boundaryEntries = [
        entry(amount: 10, date: start),
        entry(amount: 20, date: end),
      ];
      expect(
        FinanceEngine.totals(boundaryEntries, start, end, 'RUB').expense,
        10,
      );
    });
    test('overall budget covers all expense categories only', () {
      const budget = Budget(id: 'all', name: 'Общий', limitMinor: 50000);
      expect(FinanceEngine.budgetSpent(budget, entries, start, end), 35000);
    });
    test('category budget includes selected category only', () {
      const budget = Budget(
        id: 'food',
        name: 'Продукты',
        categoryId: 'food',
        limitMinor: 30000,
      );
      expect(FinanceEngine.budgetSpent(budget, entries, start, end), 25000);
    });
    test('groups expenses without mixing income, transfers or currencies', () {
      expect(
        FinanceEngine.categoryTotals(
          entries,
          start,
          end,
          'RUB',
          EntryKind.expense,
        ),
        {'food': 25000, 'transport': 10000},
      );
      expect(
        FinanceEngine.categoryTotals(
          entries,
          start,
          end,
          'RUB',
          EntryKind.income,
        ),
        {'salary': 100000},
      );
    });
    test('empty period returns zeros', () {
      expect(FinanceEngine.totals([], start, end, 'RUB'), (
        income: 0,
        expense: 0,
        net: 0,
      ));
    });
  });

  group('Entry validation', () {
    test('valid expense and income are accepted', () {
      FinanceEngine.validateEntry(entry(), data);
      FinanceEngine.validateEntry(
        entry(kind: EntryKind.income, category: 'salary'),
        data,
      );
    });
    test('rejects zero, negative and unsafe amounts', () {
      for (final amount in [0, -1, FinanceEngine.maxMinor + 1]) {
        expect(
          () => FinanceEngine.validateEntry(entry(amount: amount), data),
          throwsFormatException,
        );
      }
    });
    test('rejects missing accounts and mismatched account currencies', () {
      expect(
        () => FinanceEngine.validateEntry(entry(account: 'missing'), data),
        throwsFormatException,
      );
      expect(
        () => FinanceEngine.validateEntry(entry(currency: 'USD'), data),
        throwsFormatException,
      );
    });
    test('requires category matching operation kind', () {
      expect(
        () => FinanceEngine.validateEntry(entry(category: null), data),
        throwsFormatException,
      );
      expect(
        () => FinanceEngine.validateEntry(entry(category: 'salary'), data),
        throwsFormatException,
      );
    });
    test('requires coordinate pair and valid ranges', () {
      expect(
        () => FinanceEngine.validateEntry(
          entry().copyWith(latitude: 91.0, longitude: 0.0),
          data,
        ),
        throwsFormatException,
      );
      expect(
        () =>
            FinanceEngine.validateEntry(entry().copyWith(latitude: 55.0), data),
        throwsFormatException,
      );
      FinanceEngine.validateEntry(
        entry().copyWith(latitude: 55.75, longitude: 37.61),
        data,
      );
    });
    test('rejects unsupported status', () {
      expect(
        () => FinanceEngine.validateEntry(entry(status: 'unknown'), data),
        throwsFormatException,
      );
    });
  });

  group('Calendar recurrence', () {
    RecurringRule rule(
      DateTime date, {
      String frequency = 'monthly',
      int interval = 1,
    }) => RecurringRule(
      id: 'rent',
      name: 'Аренда',
      accountId: 'bank',
      amountMinor: 10000,
      nextDate: date,
      frequency: frequency,
      interval: interval,
    );
    test('month-end survives February and returns to March 31', () {
      final original = rule(DateTime(2026, 1, 31));
      final february = FinanceEngine.nextOccurrence(original);
      expect(february, DateTime(2026, 2, 28));
      expect(
        FinanceEngine.nextOccurrence(original.copyWith(nextDate: february)),
        DateTime(2026, 3, 31),
      );
    });
    test('30th anchor survives February without drifting to month end', () {
      final original = rule(DateTime(2026, 1, 30));
      final february = FinanceEngine.nextOccurrence(original);
      expect(february, DateTime(2026, 2, 28));
      expect(
        FinanceEngine.nextOccurrence(original.copyWith(nextDate: february)),
        DateTime(2026, 3, 30),
      );
    });
    test('28th is not incorrectly treated as an end-of-month anchor', () {
      expect(
        FinanceEngine.nextOccurrence(rule(DateTime(2026, 2, 28))),
        DateTime(2026, 3, 28),
      );
    });
    test('anchor day is persisted and old archives infer it from nextDate', () {
      final original = rule(DateTime(2026, 1, 30));
      final clamped = original.copyWith(nextDate: DateTime(2026, 2, 28));
      final restored = RecurringRule.fromJson(clamped.toJson());
      expect(restored.anchorDay, 30);
      expect(FinanceEngine.nextOccurrence(restored), DateTime(2026, 3, 30));
      final legacy = original.toJson()..remove('anchorDay');
      expect(RecurringRule.fromJson(legacy).anchorDay, 30);
      expect(
        () => FinanceEngine.nextOccurrence(original.copyWith(anchorDay: 0)),
        throwsFormatException,
      );
    });
    test('monthly date stays unchanged when available', () {
      expect(
        FinanceEngine.nextOccurrence(rule(DateTime(2026, 1, 15))),
        DateTime(2026, 2, 15),
      );
    });
    test('handles leap years and annual leap-day recurrence', () {
      expect(
        FinanceEngine.nextOccurrence(rule(DateTime(2028, 1, 31))),
        DateTime(2028, 2, 29),
      );
      expect(
        FinanceEngine.nextOccurrence(
          rule(DateTime(2028, 2, 29), frequency: 'yearly'),
        ),
        DateTime(2029, 2, 28),
      );
      final leapRule = rule(DateTime(2028, 2, 29), frequency: 'yearly');
      expect(
        FinanceEngine.nextOccurrence(
          leapRule.copyWith(nextDate: DateTime(2031, 2, 28)),
        ),
        DateTime(2032, 2, 29),
      );
    });
    test('weekly and custom intervals advance in calendar days', () {
      expect(
        FinanceEngine.nextOccurrence(
          rule(DateTime(2026, 12, 29), frequency: 'weekly', interval: 2),
        ),
        DateTime(2027, 1, 12),
      );
      expect(
        FinanceEngine.nextOccurrence(
          rule(DateTime(2026, 11, 4), frequency: 'custom', interval: 3),
        ),
        DateTime(2026, 11, 7),
      );
    });
    test('retains UTC and time of day', () {
      expect(
        FinanceEngine.nextOccurrence(rule(DateTime.utc(2026, 11, 4, 12, 30))),
        DateTime.utc(2026, 12, 4, 12, 30),
      );
    });
    test('rejects invalid recurrence values', () {
      expect(
        () => FinanceEngine.nextOccurrence(rule(start, interval: 0)),
        throwsFormatException,
      );
      expect(
        () => FinanceEngine.nextOccurrence(rule(start, frequency: 'never')),
        throwsFormatException,
      );
    });
  });

  group('Persistence model serialization', () {
    test(
      'complete snapshot round trips without changing minor units or dates',
      () {
        final snapshot = data.copyWith(
          entries: [
            entry().copyWith(
              tags: ['семья'],
              note: 'Ужин',
              latitude: 55.75,
              longitude: 37.61,
            ),
          ],
          goals: [
            Goal(
              id: 'trip',
              name: 'Отпуск',
              targetMinor: 500000,
              deadline: DateTime(2027, 7),
            ),
          ],
          budgets: const [
            Budget(id: 'food', name: 'Продукты', limitMinor: 200000),
          ],
          recurring: [
            RecurringRule(
              id: 'rent',
              name: 'Аренда',
              accountId: 'bank',
              amountMinor: 100000,
              nextDate: start,
            ),
          ],
          members: const [Member(id: 'me', name: 'Я')],
        );
        expect(
          FinanceData.fromJson(snapshot.toJson()).toJson(),
          snapshot.toJson(),
        );
      },
    );
    test('copyWith permits explicit clearing of nullable properties', () {
      expect(
        entry(category: 'food').copyWith(categoryId: null).categoryId,
        isNull,
      );
      const budget = Budget(
        id: 'food',
        name: 'Продукты',
        categoryId: 'food',
        limitMinor: 1000,
      );
      expect(budget.copyWith(categoryId: null).categoryId, isNull);
    });
  });
}
