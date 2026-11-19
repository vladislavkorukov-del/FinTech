import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/finance_engine.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/features/finora_ai/memory/assistant_preferences.dart';
import 'package:finora/features/finora_ai/ui/debt_planning_screen.dart';
import 'package:finora/features/finora_ai/ui/scenario_run_screen.dart';
import 'package:finora/presentation/controller.dart';
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

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late FinanceRepository repo;
  late FinanceController c;
  final now = DateTime.now();
  final due = DateTime(now.year, now.month, now.day + 2);

  Future<void> start(WidgetTester tester, Widget screen) async {
    await initializeDateFormatting('ru');
    dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('finora-planner-ui-'),
    ))!;
    repo = (await tester.runAsync(
      () => FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/finance.db',
      ),
    ))!;
    final fixture = FinanceData(
      accounts: const [
        Account(id: 'cash', name: 'Наличные', openingMinor: 100000),
      ],
      categories: const [
        Category(id: 'debt', name: 'Долги', kind: EntryKind.expense),
      ],
      members: const [Member(id: 'me', name: 'Я')],
      recurring: [
        RecurringRule(
          id: 'loan',
          name: 'Договор',
          accountId: 'cash',
          categoryId: 'debt',
          kind: EntryKind.expense,
          amountMinor: 30000,
          totalMinor: 60000,
          nextDate: due,
          frequency: 'monthly',
        ),
      ],
      preferences: const AppPreferences(ai: AiSettings(personalization: false)),
    );
    await tester.runAsync(() => repo.save(fixture));
    c = FinanceController(repo, _Quiet(), fixture);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinanceScope(
        controller: c,
        child: MaterialApp(
          theme: AppTheme.app(Brightness.dark, 'tropic'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(builder: (_) => screen),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.runAsync(repo.close);
    await tester.runAsync(() => dir.delete(recursive: true));
  }

  testWidgets(
    '320px planner previews, rejects cancelled confirmation and saves only pending rows',
    (tester) async {
      await start(
        tester,
        const DebtPlanningScreen(initialSourceAccountId: 'cash'),
      );
      await tester.enterText(
        find.byKey(const ValueKey('debt-plan-budget')),
        '600',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('debt-plan-compute')),
      );
      await tester.tap(find.byKey(const ValueKey('debt-plan-compute')));
      await tester.pumpAndSettle();
      expect(c.data.entries, isEmpty);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('debt-plan-save')),
        350,
        scrollable: find
            .descendant(
              of: find.byType(DebtPlanningScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('debt-plan-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('debt-plan-save')));
      await tester.pumpAndSettle();
      expect(find.text('Сохранить план в календарь?'), findsOneWidget);
      await tester.ensureVisible(find.text('Отмена').last);
      await tester.tap(find.text('Отмена').last);
      await tester.pumpAndSettle();
      expect(c.data.entries, isEmpty);
      await tester.tap(find.byKey(const ValueKey('debt-plan-save')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('finora-confirm-yes')),
      );
      await tester.tap(find.byKey(const ValueKey('finora-confirm-yes')));
      for (var i = 0; i < 100 && c.data.entries.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      expect(c.data.entries, isNotEmpty);
      expect(c.data.entries.every((e) => e.status == 'pending'), isTrue);
      expect(
        FinanceEngine.balance(c.data.accounts.single, c.data.entries),
        100000,
      );
      expect(tester.takeException(), isNull);
      await stop(tester);
    },
  );

  testWidgets(
    'saved weekly review updates from changed ledger rather than old answer',
    (tester) async {
      final scenario = SavedAssistantScenario(
        id: 'weekly',
        name: 'Недельный разбор',
        updatedAt: now,
        steps: [
          ScenarioStep(
            type: ScenarioStepType.summary,
            parameters: {'period': 'week'},
          ),
        ],
      );
      await start(tester, ScenarioRunScreen(scenario: scenario));
      expect(find.textContaining('Расходы: 0'), findsOneWidget);
      await tester.runAsync(
        () => c.saveEntry(
          FinanceEntry(
            id: 'new-real-expense',
            kind: EntryKind.expense,
            amountMinor: 500,
            currency: 'RUB',
            accountId: 'cash',
            categoryId: 'debt',
            date: now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Расходы: 5'), findsOneWidget);
      expect(find.textContaining('Расходы: 0'), findsNothing);
      expect(tester.takeException(), isNull);
      await stop(tester);
    },
  );
}
