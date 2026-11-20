import 'dart:io';

import 'package:finora/data/demo_data.dart';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/controller_phase8.dart';
import 'package:finora/presentation/screens/phase8/data_health_screen.dart';
import 'package:finora/presentation/screens/phase8/goal_funding_screen.dart';
import 'package:finora/presentation/screens/phase8/income_plan_screen.dart';
import 'package:finora/presentation/screens/phase8/prices_screen.dart';
import 'package:finora/presentation/screens/phase8/purchases_screen.dart';
import 'package:finora/presentation/screens/phase8/rules_screen.dart';
import 'package:finora/presentation/screens/phase8/split_screen.dart';
import 'package:finora/presentation/screens/phase8/time_machine_screen.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

/// Phase 8 with the real repository: migration, persistence, backups,
/// the journal, rules through saves, and every screen on real data.
void main() {
  sqfliteFfiInit();
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('finora-p8-'));
  tearDown(() async => dir.delete(recursive: true));

  FinanceData seed() {
    final demo = createDemoData(DateTime.now());
    return demo.copyWith(demo: false);
  }

  test(
    'schema 8 → 9 keeps the data; new fields and the journal appear',
    () async {
      var repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/f.db',
      );
      final data = seed();
      await repo.save(data);
      await repo.close();
      final db = await databaseFactoryFfi.openDatabase('${dir.path}/f.db');
      for (final col in ['purpose', 'recordedAt']) {
        await db.execute('ALTER TABLE entries DROP COLUMN $col');
      }
      await db.execute('DROP TABLE history');
      await db.delete('settings', where: 'key = ?', whereArgs: ['extras']);
      await db.setVersion(8);
      await db.close();
      repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/f.db',
      );
      final loaded = await repo.load();
      expect(loaded.entries.length, data.entries.length);
      expect(loaded.accounts.length, data.accounts.length);
      expect(loaded.entries.every((e) => e.purpose == null), isTrue);
      expect(loaded.extras.splits, isEmpty);
      expect(await repo.history(), isEmpty);
      await repo.close();
    },
  );

  test(
    'extras and the journal survive a restart and a backup restore',
    () async {
      final repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/f.db',
      );
      final base = seed();
      final c = FinanceController(repo, _Quiet(), base);
      final expense = base.entries.firstWhere(
        (e) => e.kind == EntryKind.expense && e.status == 'posted',
      );
      await c.splitEntry(
        expense,
        own: expense.amountMinor - expense.amountMinor ~/ 2,
        names: ['Аня'],
        parts: [expense.amountMinor ~/ 2],
      );
      final rec = await c.reconcile(base.accounts.first.id, 123400);
      await c.adjustBalance(rec.id);
      await c.saveGoalFunding(
        GoalFunding(
          budgetMinor: 1000000,
          plans: [GoalPlan(goalId: base.goals.first.id, monthlyMinor: 500000)],
        ),
      );
      await c.savePurchase(
        Purchase(
          id: 'p',
          name: 'Чайник',
          date: DateTime.now(),
          priceMinor: 300000,
        ),
      );
      await c.saveProduct(
        Product(
          id: 'milk',
          name: 'Молоко',
          unit: 'l',
          prices: [
            PriceRecord(
              id: 'r',
              date: DateTime.now(),
              store: 'Магнит',
              priceMinor: 9900,
              sizeMilli: 900,
            ),
          ],
        ),
      );
      // The adjustment brought the ledger to the bank's figure.
      final account = c.data.accounts.first;
      expect(
        c.data.entries.where((e) => e.purpose == FinanceEntry.adjustment),
        hasLength(1),
      );
      expect(c.data.extras.reconciliations.single.adjustmentEntryId, isNotNull);
      final reloaded = await repo.load();
      expect(reloaded.extras.splits, hasLength(1));
      expect(reloaded.extras.reconciliations, hasLength(1));
      expect(reloaded.extras.goalFunding.budgetMinor, 1000000);
      expect(reloaded.extras.purchases.single.name, 'Чайник');
      expect(reloaded.extras.products.single.prices.single.sizeMilli, 900);
      expect(reloaded.entries.where((e) => e.recordedAt != null), isNotEmpty);
      final history = await repo.history();
      expect(history.where((e) => e.kind == 'snapshot'), isNotEmpty);
      expect(history.where((e) => e.kind == 'goalFunding'), hasLength(1));
      expect(history.where((e) => e.kind == 'reconciliation'), hasLength(1));
      // Backup → another installation.
      final json = await repo.exportJson();
      final other = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/g.db',
      );
      await other.importJson(json);
      final restored = await other.load();
      expect(restored.extras.splits.single.shares.single.name, 'Аня');
      expect(restored.extras.purchases, hasLength(1));
      expect((await other.history()).length, history.length);
      expect(
        restored.accounts.firstWhere((a) => a.id == account.id).name,
        account.name,
      );
      c.dispose();
      await repo.close();
      await other.close();
    },
  );

  test(
    'a rule runs through a save once; a second save repeats nothing',
    () async {
      final repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/f.db',
      );
      final base = seed();
      final c = FinanceController(repo, _Quiet(), base);
      final goal = base.goals.first;
      await c.saveRule(
        PersonalRule(
          id: 'r',
          name: 'Проект — в цель',
          trigger: 'income',
          conditions: const [
            {'field': 'payee', 'value': 'проект'},
          ],
          actions: [
            {
              'type': 'suggestGoals',
              'shares': {goal.id: 10},
            },
          ],
        ),
      );
      final incomeCat = base.categories.firstWhere(
        (k) => k.kind == EntryKind.income,
      );
      final income = FinanceEntry(
        id: 'inc',
        kind: EntryKind.income,
        amountMinor: 2000000,
        currency: 'RUB',
        accountId: base.accounts.first.id,
        categoryId: incomeCat.id,
        payee: 'Оплата за проект',
        date: DateTime.now(),
      );
      await c.saveEntry(income);
      expect(c.data.extras.notices, hasLength(1));
      // Editing the same income is not a new event.
      await c.saveEntry(income.copyWith(note: 'аванс'));
      expect(c.data.extras.notices, hasLength(1));
      // After a restart the run is still known.
      final again = FinanceController(repo, _Quiet(), await repo.load());
      await again.mutate((d) => d);
      expect(again.data.extras.notices, hasLength(1));
      // Applying sets the money aside in the goal (inside the app).
      final before = again.data.entries.length;
      await again.applyNotice(again.data.extras.notices.single);
      expect(again.data.entries.length, before + 1);
      expect(again.data.entries.last.toGoalId, goal.id);
      expect(again.data.extras.notices.single.done, isTrue);
      c.dispose();
      again.dispose();
      await repo.close();
    },
  );

  for (final (name, screen) in <(String, Widget Function(FinanceData))>[
    ('time machine', (_) => const TimeMachineScreen()),
    ('goal funding', (_) => const GoalFundingScreen()),
    ('income plan', (_) => const IncomePlanScreen()),
    ('data health', (_) => const DataHealthScreen()),
    ('purchases', (_) => const PurchasesScreen()),
    ('prices', (_) => const PricesScreen()),
    ('rules', (_) => const RulesScreen()),
    (
      'split',
      (d) => SplitScreen(
        entryId: d.entries.firstWhere((e) => e.kind == EntryKind.expense).id,
      ),
    ),
  ]) {
    testWidgets('$name opens on real data without errors', (tester) async {
      await initializeDateFormatting('ru');
      final repo = (await tester.runAsync(
        () => FinanceRepository.open(
          factory: databaseFactoryFfi,
          path: '${dir.path}/$name.db',
        ),
      ))!;
      await tester.runAsync(() => repo.save(seed()));
      final c = FinanceController(
        repo,
        _Quiet(),
        (await tester.runAsync(repo.load))!,
      );
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        FinanceScope(
          controller: c,
          child: MaterialApp(
            theme: AppTheme.app(Brightness.light, 'tropic'),
            home: screen(c.data),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      expect(find.byType(Scaffold), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await tester.runAsync(repo.close);
    });
  }

  testWidgets('split from the screen: equal parts, then a partial return', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    final repo = (await tester.runAsync(
      () => FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/s.db',
      ),
    ))!;
    final data = seed();
    final bill = FinanceEntry(
      id: 'bill',
      kind: EntryKind.expense,
      amountMinor: 600000,
      currency: 'RUB',
      accountId: data.accounts.first.id,
      categoryId: data.categories
          .firstWhere((k) => k.kind == EntryKind.expense)
          .id,
      payee: 'Ресторан',
      date: DateTime.now(),
    );
    await tester.runAsync(
      () => repo.save(data.copyWith(entries: [...data.entries, bill])),
    );
    final c = FinanceController(
      repo,
      _Quiet(),
      (await tester.runAsync(repo.load))!,
    );
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinanceScope(
        controller: c,
        child: MaterialApp(
          theme: AppTheme.app(Brightness.light, 'tropic'),
          home: const SplitScreen(entryId: 'bill'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('split-name-0')), 'Аня');
    await tester.enterText(find.byKey(const ValueKey('split-name-1')), 'Боря');
    await tester.pump();
    expect(find.byKey(const ValueKey('split-preview')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('split-save')));
    for (var i = 0; i < 60 && c.data.extras.splits.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final split = c.data.extras.splits.single;
    expect(split.ownShareMinor, 200000);
    expect(find.byKey(const ValueKey('split-summary')), findsOneWidget);
    await tester.tap(
      find.byKey(ValueKey('split-repay-${split.shares.first.ruleId}')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('split-repay-amount')),
      '500',
    );
    await tester.tap(find.byKey(const ValueKey('split-repay-save')));
    for (
      var i = 0;
      i < 60 &&
          !c.data.entries.any((e) => e.purpose == FinanceEntry.reimbursement);
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final back = c.data.entries.where((e) => e.purpose == FinanceEntry.reimbursement).toList();
    expect(back.single.amountMinor, 50000);
    expect(find.textContaining(RegExp(r'1\s500')), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.runAsync(repo.close);
  });
}
