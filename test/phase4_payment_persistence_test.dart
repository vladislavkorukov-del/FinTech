import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/finance_engine.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/payment_plan.dart';
import 'package:finora/domain/weekly_debt_plan.dart';
import 'package:finora/features/finora_ai/memory/assistant_preferences.dart';
import 'package:finora/features/finora_ai/services/assistant_scenarios.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

void main() {
  sqfliteFfiInit();
  final today = DateTime(2026, 11, 18);
  final due = DateTime(2026, 11, 20);
  final rule = RecurringRule(
    id: 'loan',
    name: 'Рассрочка',
    accountId: 'cash',
    categoryId: 'debt',
    kind: EntryKind.expense,
    amountMinor: 30000,
    totalMinor: 60000,
    frequency: 'monthly',
    nextDate: due,
  );
  FinanceData fixture() => FinanceData(
    accounts: const [
      Account(id: 'cash', name: 'Наличные', openingMinor: 100000),
    ],
    categories: const [
      Category(id: 'debt', name: 'Долги', kind: EntryKind.expense),
    ],
    members: const [Member(id: 'me', name: 'Я')],
    recurring: [rule],
    preferences: const AppPreferences(ai: AiSettings(personalization: false)),
  );
  FinanceEntry scheduled({int amount = 10000, String status = 'pending'}) =>
      FinanceEntry(
        id: 'debt-plan:loan:2026-11-20:0',
        kind: EntryKind.expense,
        amountMinor: amount,
        currency: 'RUB',
        accountId: 'cash',
        categoryId: 'debt',
        date: due,
        status: status,
        recurringRuleId: 'loan',
        planningBatchId: 'batch',
        plannedDueDate: due,
      );
  late Directory dir;
  late FinanceRepository repo;
  late FinanceController c;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('finora-phase4-payments-');
    repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/finance.db',
    );
    await repo.save(fixture());
    c = FinanceController(repo, _Quiet(), await repo.load());
    c.achievementClock = () => today;
  });
  tearDown(() async {
    c.dispose();
    await repo.close();
    await dir.delete(recursive: true);
  });

  test(
    'pending schedule saves atomically without changing balance/debt and persists links',
    () async {
      final request = WeeklyDebtPlanRequest(
        sourceAccountId: 'cash',
        currency: 'RUB',
        budgetMinor: 60000,
        reserveMinor: 0,
        from: today,
        until: DateTime(2026, 12, 25),
      );
      final plan = WeeklyDebtPlanner.compute(c.data, request);
      await c.mutate(plan.applyTo);
      expect(c.data.entries, isNotEmpty);
      expect(c.data.entries.every((e) => e.status == 'pending'), isTrue);
      expect(
        FinanceEngine.balance(c.data.accounts.single, c.data.entries),
        100000,
      );
      expect(PaymentPlan.of(rule, c.data.entries, now: today).leftMinor, 60000);
      final before = c.data.entries.length;
      await c.mutate(plan.applyTo);
      expect(c.data.entries.length, before);
      final reopened = await repo.load();
      expect(reopened.entries.first.recurringRuleId, 'loan');
      expect(reopened.entries.first.planningBatchId, isNotEmpty);
      expect(
        reopened.entries.singleWhere((e) => e.date == due).plannedDueDate,
        due,
      );
    },
  );

  test(
    'partial posted row reduces actual debt once; normal confirmation pays only remainder',
    () async {
      final row = scheduled();
      await c.saveEntry(row);
      expect(PaymentPlan.of(rule, c.data.entries, now: today).paidMinor, 0);
      await c.saveEntry(row.copyWith(status: 'posted'));
      expect(PaymentPlan.of(rule, c.data.entries, now: today).leftMinor, 50000);
      expect(c.data.recurring.single.nextDate, due);
      final paid = await c.confirmPayment(
        'loan',
        expectedDueDate: due,
        confirmationId: 'one-user-confirmation',
      );
      expect(paid!.amountMinor, 20000);
      expect(
        FinanceEngine.balance(c.data.accounts.single, c.data.entries),
        70000,
      );
      expect(
        PaymentPlan.of(
          c.data.recurring.single,
          c.data.entries,
          now: today,
        ).leftMinor,
        30000,
      );
      expect(c.data.recurring.single.nextDate, DateTime(2026, 12, 20));
      await c.confirmPayment(
        'loan',
        expectedDueDate: due,
        confirmationId: 'one-user-confirmation',
      );
      expect(c.data.entries.where((e) => e.status == 'posted').length, 2);
      expect(
        FinanceEngine.balance(c.data.accounts.single, c.data.entries),
        70000,
      );
    },
  );

  test(
    'posting same planned row twice does not advance contract twice',
    () async {
      final row = scheduled(amount: 30000);
      await c.saveEntry(row);
      await c.saveEntry(row.copyWith(status: 'posted'));
      await c.saveEntry(row.copyWith(status: 'posted'));
      expect(c.data.entries.length, 1);
      expect(c.data.recurring.single.nextDate, DateTime(2026, 12, 20));
      expect(
        PaymentPlan.of(
          c.data.recurring.single,
          c.data.entries,
          now: today,
        ).leftMinor,
        30000,
      );
    },
  );

  test(
    'stale confirmation cannot silently pay the following contract date',
    () async {
      await c.confirmPayment(
        'loan',
        expectedDueDate: due,
        confirmationId: 'first',
      );
      final before = c.data.toJson();
      await expectLater(
        c.confirmPayment(
          'loan',
          expectedDueDate: due,
          confirmationId: 'stale-second',
        ),
        throwsFormatException,
      );
      expect(c.data.toJson(), before);
    },
  );

  test(
    'reducing an already posted payment restores its original unpaid date',
    () async {
      final row = scheduled(amount: 30000, status: 'posted');
      await c.saveEntry(row);
      expect(c.data.recurring.single.nextDate, DateTime(2026, 12, 20));
      await c.saveEntry(row.copyWith(amountMinor: 10000));
      expect(c.data.recurring.single.nextDate, due);
      expect(
        PaymentPlan.requiredForOccurrence(
          c.data.recurring.single,
          c.data.entries,
          due,
          now: today,
        ),
        20000,
      );
      expect(
        FinanceEngine.balance(c.data.accounts.single, c.data.entries),
        90000,
      );
    },
  );

  for (final action in ['pending', 'cancelled', 'delete']) {
    test(
      'undo a completed debt by $action restores debt and original date',
      () async {
        final row = scheduled(amount: 60000, status: 'posted');
        await c.saveEntry(row);
        expect(c.data.recurring.single.enabled, isFalse);
        if (action == 'delete') {
          await c.deleteEntry(row.id);
        } else {
          await c.saveEntry(row.copyWith(status: action));
        }
        final restored = c.data.recurring.single;
        expect(restored.enabled, isTrue);
        expect(restored.nextDate, due);
        expect(
          PaymentPlan.of(restored, c.data.entries, now: today).leftMinor,
          60000,
        );
        expect(
          FinanceEngine.balance(c.data.accounts.single, c.data.entries),
          100000,
        );
      },
    );
  }

  test(
    'changed contract invalidates an open confirmation without ledger writes',
    () async {
      await c.saveAccount(const Account(id: 'card', name: 'Карта'));
      await c.saveRecurring(rule.copyWith(accountId: 'card'));
      final before = c.data.toJson();
      await expectLater(
        c.confirmPayment('loan', expectedRule: rule, expectedDueDate: due),
        throwsFormatException,
      );
      expect(c.data.toJson(), before);
    },
  );

  test(
    'confirmed planned source is used and changing that row invalidates the dialog',
    () async {
      await c.saveAccount(
        const Account(id: 'card', name: 'Карта', openingMinor: 100000),
      );
      final row = scheduled(amount: 30000).copyWith(accountId: 'card');
      await c.saveEntry(row);
      await c.saveEntry(row.copyWith(amountMinor: 20000));
      await expectLater(
        c.confirmPayment('loan', expectedRule: rule, expectedPlannedEntry: row),
        throwsFormatException,
      );
      expect(c.data.entries.every((e) => e.status == 'pending'), isTrue);
      final paid = await c.confirmPayment(
        'loan',
        expectedRule: rule,
        expectedPlannedEntry: c.data.entries.single,
      );
      expect(paid!.accountId, 'card');
      expect(paid.amountMinor, 30000);
      expect(
        FinanceEngine.balance(c.data.accounts.first, c.data.entries),
        100000,
      );
      expect(
        FinanceEngine.balance(c.data.accounts.last, c.data.entries),
        70000,
      );
    },
  );

  test(
    'removed obligation rejects the open confirmation instead of reporting payment',
    () async {
      await c.mutate((d) => d.copyWith(recurring: []));
      await expectLater(
        c.confirmPayment('loan', expectedRule: rule, expectedDueDate: due),
        throwsFormatException,
      );
      expect(c.data.entries, isEmpty);
    },
  );

  test('archived source cannot be used for confirmed payment', () async {
    await c.saveAccount(c.data.accounts.single.copyWith(archived: true));
    final before = c.data.toJson();
    await expectLater(c.confirmPayment('loan'), throwsFormatException);
    expect(c.data.toJson(), before);
  });

  test('editing legacy posted payment also restores unpaid due date', () async {
    final paid = await c.confirmPayment('loan');
    final legacy = paid!.copyWith(
      recurringRuleId: null,
      planningBatchId: null,
      plannedDueDate: null,
    );
    await c.saveEntry(legacy);
    await c.saveEntry(legacy.copyWith(amountMinor: 10000));
    expect(c.data.recurring.single.nextDate, due);
    expect(
      PaymentPlan.requiredForOccurrence(
        c.data.recurring.single,
        c.data.entries,
        due,
        now: today,
      ),
      20000,
    );
  });

  test(
    'independent schema7 rows upgrade safely with nullable plan metadata',
    () async {
      await c.saveEntry(
        scheduled().copyWith(
          recurringRuleId: null,
          planningBatchId: null,
          plannedDueDate: null,
        ),
      );
      c.dispose();
      await repo.close();
      final db = await databaseFactoryFfi.openDatabase(
        '${dir.path}/finance.db',
      );
      for (final col in [
        'recurringRuleId',
        'planningBatchId',
        'plannedDueDate',
      ]) {
        await db.execute('ALTER TABLE entries DROP COLUMN $col');
      }
      await db.setVersion(7);
      await db.close();
      repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/finance.db',
      );
      final loaded = await repo.load();
      expect(loaded.accounts.single.openingMinor, 100000);
      expect(loaded.entries.single.status, 'pending');
      expect(loaded.entries.single.recurringRuleId, isNull);
      expect(loaded.recurring.single.totalMinor, 60000);
      expect(loaded.members.single.id, 'me');
      c = FinanceController(repo, _Quiet(), loaded);
    },
  );

  test(
    'saved debt scenario obtains current balance and detects new shortage',
    () {
      final step = ScenarioStep(
        type: ScenarioStepType.debtPlan,
        parameters: {
          'sourceAccountId': 'cash',
          'currency': 'RUB',
          'budgetMinor': 60000,
          'reserveMinor': 0,
          'horizonDays': 28,
        },
      );
      final original = AssistantScenarios.debtPlan(fixture(), step, now: today);
      expect(original.canSave, isTrue);
      final current = fixture().copyWith(
        accounts: [fixture().accounts.single.copyWith(openingMinor: 1000)],
      );
      final fresh = AssistantScenarios.debtPlan(current, step, now: today);
      expect(fresh.canSave, isFalse);
      expect(fresh.shortages, isNotEmpty);
      expect(fresh.initialBalanceMinor, 1000);
    },
  );
}
