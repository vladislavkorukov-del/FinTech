import 'package:finora/domain/finance_engine.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/payment_plan.dart';
import 'package:finora/domain/weekly_debt_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final from = DateTime(2026, 11, 18);
  final until = DateTime(2026, 12, 3);
  const categories = [
    Category(id: 'loan', name: 'Кредит', kind: EntryKind.expense),
    Category(id: 'rent', name: 'Жильё', kind: EntryKind.expense),
    Category(id: 'salary', name: 'Зарплата', kind: EntryKind.income),
  ];
  RecurringRule debt({
    String id = 'loan-1',
    String account = 'cash',
    String currency = 'RUB',
    int amount = 10000,
    int total = 100000,
    DateTime? due,
    EntryKind kind = EntryKind.expense,
  }) => RecurringRule(
    id: id,
    name: id,
    accountId: account,
    currency: currency,
    categoryId: kind == EntryKind.income ? 'salary' : 'loan',
    kind: kind,
    amountMinor: amount,
    totalMinor: total,
    nextDate: due ?? DateTime(2026, 11, 19),
    frequency: 'weekly',
  );
  FinanceData data({
    int opening = 100000,
    List<FinanceEntry> entries = const [],
    List<RecurringRule>? rules,
    List<Account> extraAccounts = const [],
  }) => FinanceData(
    accounts: [
      Account(id: 'cash', name: 'Наличные', openingMinor: opening),
      ...extraAccounts,
    ],
    categories: categories,
    members: const [Member(id: 'me', name: 'Я')],
    recurring: rules ?? [debt()],
    entries: entries,
  );
  WeeklyDebtPlanRequest request({
    int budget = 60000,
    int reserve = 0,
    DateTime? end,
    int weekday = DateTime.monday,
  }) => WeeklyDebtPlanRequest(
    sourceAccountId: 'cash',
    currency: 'RUB',
    budgetMinor: budget,
    reserveMinor: reserve,
    from: from,
    until: end ?? until,
    planningWeekday: weekday,
  );
  FinanceEntry pending(
    String id,
    int amount,
    DateTime date, {
    EntryKind kind = EntryKind.expense,
  }) => FinanceEntry(
    id: id,
    kind: kind,
    amountMinor: amount,
    currency: 'RUB',
    accountId: 'cash',
    categoryId: kind == EntryKind.income ? 'salary' : 'rent',
    date: date,
    status: 'pending',
  );

  test(
    'uses actual contractual dates and calendar weeks, not monthlybudget dividedbyfour',
    () {
      final plan = WeeklyDebtPlanner.compute(data(), request());
      expect(plan.canSave, isTrue);
      expect(plan.rows.map((r) => r.amountMinor), [10000, 10000, 10000]);
      expect(plan.rows.map((r) => r.proposedDate), [
        DateTime(2026, 11, 19),
        DateTime(2026, 11, 26),
        DateTime(2026, 12, 3),
      ]);
      expect(plan.weeks.map((w) => w.start), [
        DateTime(2026, 11, 16),
        DateTime(2026, 11, 23),
        DateTime(2026, 11, 30),
      ]);
      expect(plan.usedBudgetMinor, 30000);
      expect(plan.unusedBudgetMinor, 30000);
      expect(plan.endingBalanceMinor, 70000);
      expect(plan.debts.single.balanceMinor, 100000);
      expect(plan.debts.single.remainingAfterPlanMinor, 70000);
    },
  );

  test(
    'selected planning weekday changes grouping only, never contractdate',
    () {
      final plan = WeeklyDebtPlanner.compute(
        data(),
        request(weekday: DateTime.friday),
      );
      expect(plan.rows.first.weekStart.weekday, DateTime.friday);
      expect(plan.rows.first.proposedDate, DateTime(2026, 11, 19));
      expect(plan.rows.first.contractualDueDate, DateTime(2026, 11, 19));
    },
  );

  test('insufficient budget shows exact dated gap and cannotbe saved', () {
    final plan = WeeklyDebtPlanner.compute(data(), request(budget: 20000));
    expect(plan.canSave, isFalse);
    final missing = plan.shortages.singleWhere((s) => s.kind == 'budget');
    expect(missing.date, DateTime(2026, 12, 3));
    expect(missing.amountMinor, 10000);
    expect(() => plan.applyTo(data()), throwsFormatException);
  });

  test('salary arriving after a due date cannot erase an earlier shortage', () {
    final salary = RecurringRule(
      id: 'salary',
      name: 'Зарплата',
      accountId: 'cash',
      categoryId: 'salary',
      kind: EntryKind.income,
      amountMinor: 10000,
      nextDate: DateTime(2026, 11, 27),
      frequency: 'yearly',
    );
    final plan = WeeklyDebtPlanner.compute(
      data(opening: 15000, rules: [debt(), salary]),
      request(end: DateTime(2026, 11, 28)),
    );
    expect(plan.canSave, isFalse);
    expect(
      plan.shortages.firstWhere((s) => s.kind == 'cash').date,
      DateTime(2026, 11, 26),
    );
    expect(
      plan.shortages.firstWhere((s) => s.kind == 'cash').amountMinor,
      5000,
    );
    expect(plan.endingBalanceMinor, 5000);
  });

  test('known salary before due makes the same schedule feasible', () {
    final salary = RecurringRule(
      id: 'salary',
      name: 'Зарплата',
      accountId: 'cash',
      categoryId: 'salary',
      kind: EntryKind.income,
      amountMinor: 10000,
      nextDate: DateTime(2026, 11, 25),
      frequency: 'yearly',
    );
    final plan = WeeklyDebtPlanner.compute(
      data(opening: 15000, rules: [debt(), salary]),
      request(end: DateTime(2026, 11, 28)),
    );
    expect(plan.canSave, isTrue);
    expect(plan.endingBalanceMinor, 5000);
  });

  test('mandatory outflow and reserve are honored before debt spending', () {
    final rent = RecurringRule(
      id: 'rent',
      name: 'Аренда',
      accountId: 'cash',
      categoryId: 'rent',
      amountMinor: 6000,
      nextDate: from,
      frequency: 'yearly',
    );
    final plan = WeeklyDebtPlanner.compute(
      data(opening: 15000, rules: [debt(), rent]),
      request(reserve: 2000, end: DateTime(2026, 11, 20)),
    );
    expect(plan.rows.single.expectedBalanceMinor, -1000);
    expect(plan.shortages.last.amountMinor, 3000);
    expect(plan.canSave, isFalse);
  });

  test(
    'currencies stay separate and foreign debt is never implicitlyconverted',
    () {
      final d = data(
        rules: [
          debt(),
          debt(id: 'euro', account: 'eur', currency: 'EUR', total: 50000),
        ],
        extraAccounts: [
          const Account(id: 'eur', name: 'Евро', currency: 'EUR'),
        ],
      );
      final plan = WeeklyDebtPlanner.compute(d, request());
      expect(plan.debtTotalsByCurrency, {'RUB': 100000, 'EUR': 50000});
      expect(plan.rows.every((r) => r.ruleId == 'loan-1'), isTrue);
      expect(plan.warnings.any((w) => w.contains('EUR')), isTrue);
      expect(plan.usedBudgetMinor, 30000);
    },
  );

  test(
    'receivables are displayed but never treated as already available money',
    () {
      final plan = WeeklyDebtPlanner.compute(
        data(
          opening: 0,
          rules: [
            debt(),
            debt(id: 'owed-to-me', kind: EntryKind.income, total: 50000),
          ],
        ),
        request(end: DateTime(2026, 11, 20)),
      );
      expect(plan.receivableTotalsByCurrency, {'RUB': 50000});
      expect(plan.receivables.single.balanceMinor, 50000);
      expect(plan.initialBalanceMinor, 0);
      expect(plan.shortages.single.amountMinor, 10000);
      expect(plan.canSave, isFalse);
    },
  );

  test(
    'save creates pending calendar rows and changes neither actualbalance nor debt',
    () {
      final d = data();
      final plan = WeeklyDebtPlanner.compute(d, request());
      final saved = plan.applyTo(d);
      expect(saved.entries.length, 3);
      expect(
        saved.entries.every(
          (e) =>
              e.status == 'pending' &&
              e.recurringRuleId == 'loan-1' &&
              e.planningBatchId == plan.id,
        ),
        isTrue,
      );
      expect(saved.entries.first.plannedDueDate, DateTime(2026, 11, 19));
      expect(
        FinanceEngine.balance(saved.accounts.first, saved.entries),
        100000,
      );
      expect(
        PaymentPlan.of(
          saved.recurring.first,
          saved.entries,
          now: from,
        ).leftMinor,
        100000,
      );
      final posted = saved.copyWith(
        entries: [
          saved.entries.first.copyWith(status: 'posted'),
          ...saved.entries.skip(1),
        ],
      );
      expect(
        FinanceEngine.balance(posted.accounts.first, posted.entries),
        90000,
      );
      expect(
        PaymentPlan.of(
          posted.recurring.first,
          posted.entries,
          now: from,
        ).leftMinor,
        90000,
      );
    },
  );

  test(
    'saving twice or recomputing keeps stable occurrenceIDs withno duplicates',
    () {
      final d = data(), req = request();
      final plan = WeeklyDebtPlanner.compute(d, req);
      final saved = plan.applyTo(d);
      final twice = plan.applyTo(saved);
      expect(twice.entries.length, 3);
      final recalculated = WeeklyDebtPlanner.compute(twice, req);
      final updated = recalculated.applyTo(twice);
      expect(updated.entries.length, 3);
      expect(
        updated.entries.map((e) => e.id).toSet(),
        saved.entries.map((e) => e.id).toSet(),
      );
      expect(recalculated.usedBudgetMinor, plan.usedBudgetMinor);
      expect(recalculated.endingBalanceMinor, plan.endingBalanceMinor);
    },
  );

  test('stale cash balance invalidates old confirmation', () {
    final d = data();
    final plan = WeeklyDebtPlanner.compute(d, request());
    final changed = d.copyWith(
      accounts: [d.accounts.first.copyWith(openingMinor: 200000)],
    );
    expect(() => plan.applyTo(changed), throwsFormatException);
  });

  test('a user-edited pending row and a posted row cannotbe overwritten', () {
    final d = data();
    final plan = WeeklyDebtPlanner.compute(d, request());
    final saved = plan.applyTo(d);
    final edited = saved.copyWith(
      entries: [
        saved.entries.first.copyWith(note: 'Изменено пользователем'),
        ...saved.entries.skip(1),
      ],
    );
    expect(() => plan.applyTo(edited), throwsFormatException);
    final posted = saved.copyWith(
      entries: [
        saved.entries.first.copyWith(status: 'posted'),
        ...saved.entries.skip(1),
      ],
    );
    expect(() => plan.applyTo(posted), throwsFormatException);
  });

  test(
    'overdue contractual date remains unchanged, recovery is proposedtoday',
    () {
      final plan = WeeklyDebtPlanner.compute(
        data(rules: [debt(due: DateTime(2026, 11, 17))]),
        request(end: DateTime(2026, 11, 20)),
      );
      expect(plan.rows.single.contractualDueDate, DateTime(2026, 11, 17));
      expect(plan.rows.single.proposedDate, from);
      expect(plan.rows.single.overdue, isTrue);
      expect(plan.warnings.any((w) => w.contains('просрочено')), isTrue);
    },
  );

  test('unknown credit card conditions block a false completeplan', () {
    final plan = WeeklyDebtPlanner.compute(
      data(
        extraAccounts: [
          const Account(
            id: 'credit',
            name: 'Кредитная карта',
            type: 'credit',
            openingMinor: -10000,
          ),
        ],
      ),
      request(),
    );
    expect(plan.canSave, isFalse);
    expect(
      plan.needsConditions.any((w) => w.contains('Кредитная карта')),
      isTrue,
    );
  });

  test('negative source balance is reported on currentdate', () {
    final plan = WeeklyDebtPlanner.compute(
      data(opening: -5000),
      request(end: from),
    );
    expect(plan.shortages.single.date, from);
    expect(plan.shortages.single.amountMinor, 5000);
  });

  test('pending dated expenses and explicit transfers feed forecast only', () {
    final d = data(
      opening: 10000,
      entries: [
        pending('groceries', 5000, from),
        FinanceEntry(
          id: 'transfer',
          kind: EntryKind.transfer,
          amountMinor: 10000,
          currency: 'EUR',
          accountId: 'eur',
          toAccountId: 'cash',
          destinationMinor: 15000,
          date: from,
          status: 'pending',
        ),
      ],
      extraAccounts: [
        const Account(
          id: 'eur',
          name: 'Евро',
          currency: 'EUR',
          openingMinor: 10000,
        ),
      ],
    );
    final plan = WeeklyDebtPlanner.compute(
      d,
      request(end: DateTime(2026, 11, 20)),
    );
    expect(plan.initialBalanceMinor, 10000);
    expect(plan.endingBalanceMinor, 10000);
    expect(plan.canSave, isTrue);
  });

  test(
    'partial ordinary obligation still reserves its unpaid remainder before debt',
    () {
      final rent = RecurringRule(
        id: 'rent',
        name: 'Аренда',
        accountId: 'cash',
        categoryId: 'rent',
        amountMinor: 30000,
        nextDate: from,
        frequency: 'monthly',
      );
      final paid = FinanceEntry(
        id: 'rent-part',
        kind: EntryKind.expense,
        amountMinor: 10000,
        currency: 'RUB',
        accountId: 'cash',
        categoryId: 'rent',
        date: from,
        recurringRuleId: 'rent',
        planningBatchId: 'confirmed-payment',
        plannedDueDate: from,
      );
      final plan = WeeklyDebtPlanner.compute(
        data(
          opening: 40000,
          entries: [paid],
          rules: [rent, debt(amount: 20000)],
        ),
        request(end: DateTime(2026, 11, 20)),
      );
      expect(plan.canSave, isFalse);
      expect(
        plan.shortages.singleWhere((s) => s.kind == 'cash').amountMinor,
        10000,
      );
    },
  );

  test('loan with known interest uses existingplan and marksestimate', () {
    final loan = debt().copyWith(
      totalMinor: null,
      principalMinor: 100000,
      interestRate: 12.0,
      principalDate: from,
    );
    final plan = WeeklyDebtPlanner.compute(data(rules: [loan]), request());
    expect(plan.debts.single.approximateInterest, isTrue);
    expect(
      plan.warnings.any((w) => w.contains('проценты приблизительные')),
      isTrue,
    );
    expect(plan.rows.length, 3);
  });

  test(
    'partial actualpayment reduces currentminimum ratherthan being charged twice',
    () {
      final posted = FinanceEntry(
        id: 'partial',
        kind: EntryKind.expense,
        amountMinor: 4000,
        currency: 'RUB',
        accountId: 'cash',
        categoryId: 'loan',
        date: from,
        recurringRuleId: 'loan-1',
        plannedDueDate: DateTime(2026, 11, 19),
      );
      final plan = WeeklyDebtPlanner.compute(
        data(entries: [posted]),
        request(end: DateTime(2026, 11, 20)),
      );
      expect(plan.rows.single.amountMinor, 6000);
      expect(plan.debts.single.balanceMinor, 96000);
    },
  );

  test(
    'posting part of a plan row permits only its remainder as a new stable row',
    () {
      final d = data();
      final req = request(end: DateTime(2026, 11, 20));
      final first = WeeklyDebtPlanner.compute(d, req).applyTo(d);
      final partial = first.copyWith(
        entries: [
          first.entries.single.copyWith(amountMinor: 4000, status: 'posted'),
        ],
      );
      final remainder = WeeklyDebtPlanner.compute(partial, req);
      expect(remainder.rows.single.amountMinor, 6000);
      expect(remainder.rows.single.id, isNot(first.entries.single.id));
      final saved = remainder.applyTo(partial);
      expect(
        saved.entries.where((e) => e.status == 'posted').single.amountMinor,
        4000,
      );
      expect(
        saved.entries.where((e) => e.status == 'pending').single.amountMinor,
        6000,
      );
      expect(remainder.applyTo(saved).entries.length, 2);
    },
  );

  test(
    'recalculation replaces obsolete pending occurrence after another partial payment',
    () {
      final d = data();
      final req = request(end: DateTime(2026, 11, 20));
      final old = WeeklyDebtPlanner.compute(d, req).applyTo(d);
      final externalPayment = FinanceEntry(
        id: 'outside-payment',
        kind: EntryKind.expense,
        amountMinor: 4000,
        currency: 'RUB',
        accountId: 'cash',
        categoryId: 'loan',
        date: from,
        recurringRuleId: 'loan-1',
        plannedDueDate: DateTime(2026, 11, 19),
      );
      final updated = old.copyWith(entries: [...old.entries, externalPayment]);
      final plan = WeeklyDebtPlanner.compute(updated, req);
      final saved = plan.applyTo(updated);
      expect(saved.entries.length, 2);
      expect(
        saved.entries.where((e) => e.status == 'pending').single.amountMinor,
        6000,
      );
      expect(plan.applyTo(saved).entries.length, 2);
    },
  );

  test(
    'ordinary appearance settings do not invalidate confirmed financial facts',
    () {
      final d = data();
      final plan = WeeklyDebtPlanner.compute(d, request());
      final appearance = d.copyWith(
        preferences: d.preferences.copyWith(theme: 'light'),
      );
      expect(plan.applyTo(appearance).entries.length, 3);
    },
  );

  test('invalid source/currency and oversized horizon are rejected', () {
    expect(
      () => WeeklyDebtPlanner.compute(
        data(),
        WeeklyDebtPlanRequest(
          sourceAccountId: 'missing',
          currency: 'RUB',
          budgetMinor: 100,
          reserveMinor: 0,
          from: from,
          until: until,
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => WeeklyDebtPlanRequest(
        sourceAccountId: 'cash',
        currency: 'RUB',
        budgetMinor: 100,
        reserveMinor: 0,
        from: from,
        until: from.add(const Duration(days: 91)),
      ),
      throwsFormatException,
    );
  });
}
