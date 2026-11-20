import 'package:finora/domain/finance_engine.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/planning/bill_split.dart';
import 'package:finora/domain/planning/data_health.dart';
import 'package:finora/domain/planning/goal_planner.dart';
import 'package:finora/domain/planning/income_planner.dart';
import 'package:finora/domain/planning/journal.dart';
import 'package:finora/domain/planning/purchase_math.dart';
import 'package:finora/domain/planning/rules_engine.dart';
import 'package:finora/domain/planning/time_machine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 8 money mechanics: the numbers checked against hand calculations.
void main() {
  final now = DateTime(2026, 11, 10, 12);
  var seq = 0;
  String id() => 'id${seq++}';
  const accounts = [
    Account(id: 'card', name: 'Карта'),
    Account(id: 'cash', name: 'Наличные'),
  ];
  const categories = [
    Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
    Category(id: 'cafe', name: 'Кафе', kind: EntryKind.expense),
    Category(id: 'pay', name: 'Зарплата', kind: EntryKind.income),
  ];
  FinanceEntry expense(
    String id,
    int amount, {
    DateTime? date,
    String payee = '',
    String cat = 'cafe',
  }) => FinanceEntry(
    id: id,
    kind: EntryKind.expense,
    amountMinor: amount,
    currency: 'RUB',
    accountId: 'card',
    categoryId: cat,
    payee: payee,
    date: date ?? now,
  );

  group('Я заплатил за всех', () {
    test('equal parts: the kopeck left by rounding stays with the payer', () {
      expect(BillSplits.equal(10000, 2).$1, 3334);
      expect(BillSplits.equal(10000, 2).$2, [3333, 3333]);
      expect(BillSplits.equal(600000, 2).$1, 200000);
      expect(BillSplits.equal(600000, 2).$2, [200000, 200000]);
      expect(BillSplits.byShares(1000, [1, 1, 1]).$1, 334);
      expect(BillSplits.byShares(1000, [1, 1, 1]).$2, [333, 333]);
      expect(
        () => BillSplits.checkAmounts(600000, 200000, [200000, 100000]),
        throwsFormatException,
      );
    });

    test('6 000 ₽ for three: own 2 000, owed 4 000, partial return 500', () {
      final bill = expense('bill', 600000, payee: 'Ресторан');
      var data = const FinanceData(
        accounts: accounts,
        categories: categories,
      ).copyWith(entries: [bill]);
      data = BillSplits.create(
        data,
        entry: bill,
        own: 200000,
        names: ['Аня', 'Боря'],
        parts: [200000, 200000],
        newId: id,
        now: now,
      );
      final split = data.extras.splits.single;
      var status = BillSplits.status(data, split)!;
      expect(status.outflowMinor, 600000);
      expect(status.personalMinor, 200000);
      expect(status.initiallyOwedMinor, 400000);
      // Each person owes through the existing debt system.
      expect(
        data.recurring.where(
          (r) => r.kind == EntryKind.income && r.totalMinor == 200000,
        ),
        hasLength(2),
      );
      // Аня returns 500 ₽ — to the cash account, another account.
      data = BillSplits.repay(
        data,
        share: split.shares.first,
        amount: 50000,
        accountId: 'cash',
        date: now,
        uniqueSuffix: 'r1',
      );
      status = BillSplits.status(data, split)!;
      expect(status.shares.first.leftMinor, 150000);
      expect(status.stillOwedMinor, 350000);
      // Money back raises the balance but is not earned income.
      final cash = data.accounts.firstWhere((a) => a.id == 'cash');
      expect(FinanceEngine.balance(cash, data.entries), 50000);
      final totals = FinanceEngine.totals(
        data.entries,
        DateTime(2026, 11),
        DateTime(2026, 12),
        'RUB',
      );
      expect(totals.income, 0);
      expect(totals.expense, 600000);
      // Overpayment: no negative debt, the extra is shown, not lost.
      data = BillSplits.repay(
        data,
        share: split.shares.first,
        amount: 200000,
        accountId: 'card',
        date: now,
        uniqueSuffix: 'r2',
      );
      status = BillSplits.status(data, split)!;
      expect(status.shares.first.leftMinor, 0);
      expect(status.shares.first.overpaidMinor, 50000);
      // Cancelling the return restores the debt.
      data = BillSplits.cancelRepayment(
        data,
        status.shares.first.repayments.last.id,
      );
      expect(BillSplits.status(data, split)!.shares.first.leftMinor, 150000);
      // A person who already paid back cannot be removed.
      expect(
        () => BillSplits.edit(
          data,
          split: split,
          own: 400000,
          parts: [0, 200000],
        ),
        throwsFormatException,
      );
      final edited = BillSplits.edit(
        data,
        split: split,
        own: 300000,
        parts: [200000, 100000],
      );
      expect(
        BillSplits.status(
          edited,
          edited.extras.splits.single,
        )!.shares.last.share.shareMinor,
        100000,
      );
    });
  });

  group('Честная картина', () {
    test(
      'a reconciliation shows the difference; the adjustment is explicit',
      () {
        var data = const FinanceData(
          accounts: accounts,
          categories: categories,
        ).copyWith(entries: [expense('a', 100000)]);
        final rec = DataHealth.reconcile(
          data,
          id: 'rec',
          accountId: 'card',
          actualMinor: -95000,
          now: now,
        );
        expect(rec.bookMinor, -100000);
        expect(rec.differenceMinor, 5000);
        final report = DataHealth.check(
          data.copyWith(extras: data.extras.copyWith(reconciliations: [rec])),
          now: now,
        );
        expect(report.issues.any((i) => i.kind == 'difference'), isTrue);
        final adj = DataHealth.adjustment(rec, data, id: 'adj');
        expect(adj.purpose, FinanceEntry.adjustment);
        data = data.copyWith(entries: [...data.entries, adj]);
        FinanceEngine.validateEntry(adj, data);
        final card = data.accounts.first;
        expect(FinanceEngine.balance(card, data.entries), -95000);
        // Not income or spending.
        expect(
          FinanceEngine.totals(
            data.entries,
            DateTime(2026, 11),
            DateTime(2026, 12),
            'RUB',
          ).income,
          0,
        );
      },
    );

    test(
      'possible duplicates name what matches; stale accounts are listed',
      () {
        final data =
            const FinanceData(
              accounts: accounts,
              categories: categories,
            ).copyWith(
              entries: [
                expense('a', 45000, payee: 'Пятёрочка'),
                expense(
                  'b',
                  45000,
                  payee: 'Пятерочка',
                  date: now.add(const Duration(hours: 2)),
                ),
                expense('c', 45000, payee: 'Магнит'),
              ],
            );
        final d = DataHealth.findDuplicates(data.entries);
        expect(d, hasLength(1));
        expect(
          d.single.reasons,
          containsAll(['счёт', 'сумма', 'дата', 'получатель']),
        );
        final report = DataHealth.check(data, now: now);
        expect(report.issues.where((i) => i.kind == 'stale'), hasLength(2));
      },
    );
  });

  group('Конфликт целей', () {
    final goals = [
      Goal(
        id: 'trip',
        name: 'Отпуск',
        targetMinor: 6000000,
        deadline: DateTime(2027, 6, 15),
      ),
      const Goal(id: 'repair', name: 'Ремонт', targetMinor: 12000000),
      const Goal(id: 'reserve', name: 'Резерв', targetMinor: 3000000),
    ];
    final data = FinanceData(
      accounts: accounts,
      categories: categories,
      goals: goals,
    );

    test('one budget shared: more to one goal moves the others', () {
      final before = GoalPlanner.plan(
        data,
        now: now,
        funding: const GoalFunding(
          budgetMinor: 1500000,
          plans: [
            GoalPlan(goalId: 'reserve', monthlyMinor: 500000, protected: true),
            GoalPlan(goalId: 'trip', monthlyMinor: 500000, priority: 1),
            GoalPlan(goalId: 'repair', monthlyMinor: 500000, priority: 2),
          ],
        ),
      );
      expect(before.deficitMinor, 0);
      // 60 000 ₽ at 5 000 ₽ a month: 365 days.
      expect(before.of('trip')!.date, now.add(const Duration(days: 365)));
      final after = GoalPlanner.plan(
        data,
        now: now,
        funding: const GoalFunding(
          budgetMinor: 1500000,
          plans: [
            GoalPlan(goalId: 'reserve', monthlyMinor: 500000, protected: true),
            GoalPlan(goalId: 'trip', monthlyMinor: 800000, priority: 1),
            GoalPlan(goalId: 'repair', monthlyMinor: 500000, priority: 2),
          ],
        ),
      );
      // The budget is short by 3 000; the last goal gets only 2 000.
      expect(after.deficitMinor, 300000);
      expect(after.of('repair')!.allocatedMinor, 200000);
      expect(after.of('reserve')!.allocatedMinor, 500000);
      final shifts = {
        for (final s in GoalPlanner.compare(before, after)) s.goal.id: s.days,
      };
      expect(shifts['trip'], lessThan(0));
      expect(shifts['repair'], greaterThan(0));
      expect(shifts['reserve'], 0);
      // The deadline needs: 60 000 over 7 months.
      expect(before.of('trip')!.needMonthlyMinor, (6000000 + 6) ~/ 7);
    });

    test('no contribution — no invented date', () {
      final p = GoalPlanner.plan(data, now: now);
      expect(p.of('repair')!.date, isNull);
      expect(p.of('repair')!.reason, isNotEmpty);
    });
  });

  group('Нерегулярный доход', () {
    final rules = [
      RecurringRule(
        id: 'rent',
        name: 'Аренда',
        accountId: 'card',
        categoryId: 'food',
        amountMinor: 1240000,
        nextDate: DateTime(2026, 11, 18),
      ),
      RecurringRule(
        id: 'fee',
        name: 'Оплата проекта',
        accountId: 'card',
        categoryId: 'pay',
        kind: EntryKind.income,
        amountMinor: 2000000,
        nextDate: DateTime(2026, 11, 15),
      ),
    ];
    final data = FinanceData(
      accounts: const [
        Account(id: 'card', name: 'Карта', openingMinor: 1000000),
      ],
      categories: categories,
      recurring: rules,
    );

    test('available now vs with the expected income; no gap on time', () {
      final p = IncomePlanner.plan(data, now: now, horizonDays: 10);
      expect(p.balanceMinor, 1000000);
      expect(p.obligationsMinor, 1240000);
      expect(p.expectedMinor, 2000000);
      expect(p.availableNowMinor, -240000);
      expect(p.availableWithIncomeMinor, 1760000);
      expect(p.dailyLimitMinor, 0);
      expect(p.gapDate, isNull);
      // Expected income is not in the balance.
      expect(FinanceEngine.balance(data.accounts.first, data.entries), 1000000);
    });

    test('a 7-day delay: on the 18th 2 400 ₽ short', () {
      final p = IncomePlanner.plan(
        data,
        now: now,
        horizonDays: 20,
        scenario: const IncomeScenario(delayDays: 7),
      );
      expect(p.gapDate, DateTime(2026, 11, 18));
      expect(p.gapMinor, 240000);
      // The scenario changed nothing.
      expect(
        data.recurring.firstWhere((r) => r.id == 'fee').nextDate,
        DateTime(2026, 11, 15),
      );
    });

    test('a planned payment replaces its rule date (counted once)', () {
      final planned = FinanceEntry(
        id: 'p',
        kind: EntryKind.expense,
        amountMinor: 1240000,
        currency: 'RUB',
        accountId: 'card',
        categoryId: 'food',
        date: DateTime(2026, 11, 18),
        status: 'pending',
        recurringRuleId: 'rent',
        planningBatchId: 'b',
        plannedDueDate: DateTime(2026, 11, 18),
      );
      final p = IncomePlanner.plan(
        data.copyWith(entries: [planned]),
        now: now,
        horizonDays: 10,
      );
      expect(p.obligationsMinor, 1240000);
    });

    test('no expected income: a horizon is asked, not invented', () {
      final p = IncomePlanner.plan(
        data.copyWith(recurring: [rules.first]),
        now: now,
      );
      expect(p.needsHorizon, isTrue);
    });
  });

  group('Машина времени', () {
    test('a correction later does not rewrite the saved past', () {
      const goal = Goal(id: 'trip', name: 'Отпуск', targetMinor: 6000000);
      var data = const FinanceData(
        accounts: accounts,
        categories: categories,
        goals: [goal],
        extras: FinanceExtras(
          goalFunding: GoalFunding(
            plans: [GoalPlan(goalId: 'trip', monthlyMinor: 500000)],
          ),
        ),
      );
      final march = DateTime(2026, 3, 1, 10);
      final saved = PlanSnapshot.compute(data, march);
      final history = [
        HistoryEvent(
          id: 's1',
          at: march,
          kind: 'snapshot',
          payload: saved.json,
        ),
      ];
      // Later the plan changes and an old expense is entered afterwards.
      final before = data;
      data = data.copyWith(
        entries: [
          expense(
            'late',
            100000,
            date: DateTime(2026, 2, 20),
          ).copyWith(recordedAt: DateTime(2026, 4, 2)),
        ],
        extras: data.extras.copyWith(
          goalFunding: const GoalFunding(
            plans: [GoalPlan(goalId: 'trip', monthlyMinor: 400000)],
          ),
        ),
      );
      final events = Journal.diff(before, data, DateTime(2026, 4, 2));
      expect(events.map((e) => e.kind), containsAll(['entry', 'goalFunding']));
      final view = TimeMachine.view(
        data,
        [...history, ...events],
        DateTime(2026, 3, 1),
        now: now,
      );
      expect(view.saved, isTrue);
      expect(view.then.goals.single['monthlyMinor'], 500000);
      expect(view.lateEntries.map((e) => e.id), ['late']);
      expect(view.changes.join('\n'), contains('взнос в месяц'));
      expect(view.changes.join('\n'), contains('внесены или исправлены позже'));
      // Before any saved state: rebuilt from operations, said so.
      final early = TimeMachine.view(
        data,
        history,
        DateTime(2026, 1, 1),
        now: now,
      );
      expect(early.saved, isFalse);
    });

    test('stamping marks only new or changed operations', () {
      final a = const FinanceData(
        accounts: accounts,
        categories: categories,
      ).copyWith(entries: [expense('x', 100)]);
      final b = a.copyWith(entries: [a.entries.first, expense('y', 200)]);
      final stamped = Journal.stamp(a, b, now);
      expect(stamped.entries.first.recordedAt, isNull);
      expect(stamped.entries.last.recordedAt, now);
    });
  });

  group('Полезность покупки и цены', () {
    test('no uses — no per-use price; linked costs counted once', () {
      final bought = expense('buy', 3000000, payee: 'Кофемашина');
      final service = expense('svc', 150000, payee: 'Сервис');
      final data = const FinanceData(
        accounts: accounts,
        categories: categories,
      ).copyWith(entries: [bought, service]);
      var p = Purchase(
        id: 'p',
        name: 'Кофемашина',
        date: DateTime(2026, 1, 10),
        priceMinor: 3000000,
        entryId: 'buy',
        expectedUsesPerMonth: 30,
        expectedMonths: 24,
      );
      var c = PurchaseMath.cost(p, data, until: now);
      expect(c.uses, 0);
      expect(c.perUseMinor, isNull);
      expect(c.perExpectedUseMinor(p), (3000000 + 360) ~/ 720);
      p = p.copyWith(
        events: [
          PurchaseEvent(
            id: 'u',
            kind: 'use',
            at: DateTime(2026, 2, 1),
            count: 100,
          ),
          PurchaseEvent(
            id: 's1',
            kind: 'service',
            at: DateTime(2026, 5, 1),
            entryId: 'svc',
          ),
          PurchaseEvent(
            id: 's2',
            kind: 'service',
            at: DateTime(2026, 5, 1),
            entryId: 'svc',
          ),
          PurchaseEvent(
            id: 'r',
            kind: 'sale',
            at: DateTime(2026, 9, 1),
            amountMinor: 1000000,
          ),
        ],
      );
      c = PurchaseMath.cost(p, data, until: now);
      expect(c.upkeepMinor, 150000);
      expect(c.netMinor, 3000000 + 150000 - 1000000);
      expect(c.perUseMinor, 21500);
    });

    test('a smaller pack at the same price: +11,1 % per litre', () {
      final milk = Product(
        id: 'm',
        name: 'Молоко',
        unit: 'l',
        prices: [
          PriceRecord(
            id: '1',
            date: DateTime(2026, 1, 5),
            store: 'Магнит',
            priceMinor: 20000,
            sizeMilli: 1000,
          ),
          PriceRecord(
            id: '2',
            date: DateTime(2026, 6, 5),
            store: 'Магнит',
            priceMinor: 20000,
            sizeMilli: 900,
          ),
          PriceRecord(
            id: '3',
            date: DateTime(2026, 7, 5),
            store: 'Duty Free',
            priceMinor: 300,
            sizeMilli: 1000,
            currency: 'USD',
          ),
        ],
      );
      expect(PriceMath.perUnit(milk.prices[1]), 22222);
      final s = PriceMath.shrinks(milk);
      expect(s.single.percent, 1111);
      // Another currency is not mixed in.
      expect(PriceMath.history(milk), hasLength(2));
      expect(PriceMath.byStore(milk).single.record.store, 'Магнит');
      // Packs: 2 × 0,5 л for 120 ₽ → 120 ₽ a litre.
      expect(
        PriceMath.perUnit(
          PriceRecord(
            id: 'x',
            date: now,
            store: 'А',
            priceMinor: 12000,
            sizeMilli: 500,
            packs: 2,
          ),
        ),
        12000,
      );
    });
  });

  group('Личные правила', () {
    final goal = const Goal(
      id: 'reserve',
      name: 'Резерв',
      targetMinor: 10000000,
    );
    final budget = const Budget(
      id: 'b',
      name: 'Кафе',
      categoryId: 'cafe',
      limitMinor: 1000000,
    );
    final base = FinanceData(
      accounts: accounts,
      categories: categories,
      goals: [goal],
      budgets: [budget],
      extras: const FinanceExtras(
        rules: [
          PersonalRule(
            id: 'r1',
            name: 'Проект — 20 % в резерв',
            trigger: 'income',
            conditions: [
              {'field': 'payee', 'value': 'проект'},
            ],
            actions: [
              {
                'type': 'suggestGoals',
                'shares': {'reserve': 20},
              },
            ],
          ),
          PersonalRule(
            id: 'r2',
            name: 'Возврат — в бюджет',
            trigger: 'refund',
            actions: [
              {'type': 'restoreBudget', 'auto': true},
            ],
          ),
          PersonalRule(
            id: 'r3',
            name: 'Возврат — ещё раз в бюджет',
            trigger: 'refund',
            priority: 5,
            actions: [
              {'type': 'restoreBudget', 'auto': true},
            ],
          ),
        ],
      ),
    );
    final income = FinanceEntry(
      id: 'inc',
      kind: EntryKind.income,
      amountMinor: 5000000,
      currency: 'RUB',
      accountId: 'card',
      categoryId: 'pay',
      payee: 'Оплата за проект',
      date: now,
    );

    test('an event is processed once, also after a restart', () {
      final after = base.copyWith(entries: [income]);
      final events = RulesEngine.events(base, after, now: now);
      expect(events.single.type, 'income');
      final (once, outcomes) = RulesEngine.process(after, events, now: now);
      expect(outcomes.single.fired, isTrue);
      // 20 % of 50 000 ₽ = 10 000 ₽ to «Резерв».
      expect(once.extras.notices.single.payload['parts'], {'reserve': 1000000});
      expect(once.extras.notices.single.text, contains('Резерв'));
      // Same event again (a restart: runs are in the saved data).
      final restored = FinanceData.fromJson(once.toJson());
      final (twice, _) = RulesEngine.process(restored, events, now: now);
      expect(twice.extras.notices, hasLength(1));
      // A dry run tells why and changes nothing.
      final (dry, check) = RulesEngine.process(
        restored,
        events,
        now: now,
        dryRun: true,
      );
      expect(identical(dry, restored), isTrue);
      expect(check.single.explanation, contains('уже обработано'));
    });

    test('a refund restores the budget; a second rule does not double it', () {
      final paid = expense('buy', 300000, payee: 'Кофемания');
      final withExpense = base.copyWith(entries: [paid]);
      final refund = FinanceEntry(
        id: 'ref',
        kind: EntryKind.income,
        amountMinor: 120000,
        currency: 'RUB',
        accountId: 'card',
        categoryId: 'pay',
        payee: 'Кофемания',
        date: now,
      );
      final after = withExpense.copyWith(entries: [paid, refund]);
      final events = RulesEngine.events(withExpense, after, now: now);
      expect(events.single.type, 'refund');
      final (result, outcomes) = RulesEngine.process(after, events, now: now);
      expect(result.extras.budgetAdjustments, hasLength(1));
      expect(outcomes.last.explanation, contains('уже изменён'));
      final start = DateTime(2026, 11, 1);
      expect(RulesEngine.effectiveLimit(result, budget, start), 1120000);
      expect(
        RulesEngine.conflicts(base.extras.rules[1], base.extras.rules),
        isNotEmpty,
      );
    });

    test('a rule from a phrase, checked against the schema', () {
      final r = RulesEngine.fromPhrase(
        'Когда получаю оплату за проект, предлагай 20% в резерв',
        base,
        id,
      )!;
      expect(r.trigger, 'income');
      expect(r.enabled, isFalse);
      expect(r.actions.single['shares'], {'reserve': 20});
      expect(RulesEngine.validate(r, base), isEmpty);
      final bad = r.copyWith(
        actions: [
          {'type': 'restoreBudget'},
        ],
      );
      expect(RulesEngine.validate(bad, base), isNotEmpty);
    });
  });
}
