import 'dart:convert';
import 'dart:io';

import 'package:finora/features/finora_ai/memory/assistant_preferences.dart';
import 'package:finora/features/finora_ai/services/finora_ai.dart';
import 'package:finora/features/finora_ai/memory/personal_memory.dart';
import 'package:finora/features/finora_ai/repositories/memory_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:finora/data/demo_data.dart';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/services/notification_service.dart';
import 'package:finora/features/finora_ai/ui/assistant_memory_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

void main() {
  final at = DateTime(2026, 11, 18, 15);
  SavedAssistantScenario scenario([String id = 'weekly-review']) =>
      SavedAssistantScenario(
        id: id,
        name: 'Недельный разбор',
        updatedAt: at,
        steps: [
          ScenarioStep(
            type: ScenarioStepType.summary,
            parameters: {'period': 'week'},
          ),
          ScenarioStep(
            type: ScenarioStepType.upcomingPayments,
            parameters: {'withinDays': 7},
          ),
        ],
      );
  late Directory dir;
  late File file;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('finora-confirmed-memory-');
    file = File('${dir.path}/finora_ai_memory.json');
  });
  tearDown(() => dir.delete(recursive: true));

  test(
    'schema3 migration preserves merchant corrections, votes and excluded months',
    () async {
      final memory = PersonalMemory();
      memory.observe('магазин', 'food', previous: 'other', at: at);
      memory.excludedMonths.add('2026-10');
      memory.confirmedSubscriptions.add('subscription:music');
      final old = memory.toJson()..['version'] = 3;
      old.remove('preferences');
      old.remove('scenarios');
      await file.writeAsString(jsonEncode(old));
      final repo = MemoryRepository(file: file);
      await repo.load();
      expect(repo.memory.categoryFor('магазин')?.categoryId, 'food');
      expect(repo.memory.corrections.single.from, 'other');
      expect(repo.memory.excludedMonths, contains('2026-10'));
      expect(
        repo.memory.confirmedSubscriptions,
        contains('subscription:music'),
      );
      expect(repo.memory.preferences.primaryAccountId, isNull);
      expect(repo.memory.preferences.planningWeekday, DateTime.monday);
      await repo.setPreferences(AssistantPreferences(primaryAccountId: 'cash'));
      final reopened = MemoryRepository(file: file);
      await reopened.load();
      expect(reopened.memory.preferences.primaryAccountId, 'cash');
      expect(reopened.memory.corrections.single.from, 'other');
      expect(
        jsonDecode(await file.readAsString())['version'],
        PersonalMemory.version,
      );
    },
  );

  test(
    'confirmed planner parameters and scenarios survive restart and full-memory backup',
    () async {
      final repo = MemoryRepository(file: file);
      final preferences = AssistantPreferences(
        primaryAccountId: 'main',
        planningWeekday: DateTime.friday,
        reportFormat: AssistantReportFormat.detailed,
        plannerParams: PlannerPreferences(
          sourceAccountId: 'cash',
          budgetMinor: 123456,
          reserveMinor: 50000,
          horizonDays: 35,
        ),
      );
      await repo.setPreferences(preferences);
      await repo.saveScenario(scenario());
      final reopened = MemoryRepository(file: file);
      await reopened.load();
      final restored = PersonalMemory.fromJson(
        jsonDecode(jsonEncode(reopened.memory.toJson())),
      );
      expect(restored.preferences.reportFormat, AssistantReportFormat.detailed);
      expect(restored.preferences.plannerParams.budgetMinor, 123456);
      expect(restored.preferences.plannerParams.reserveMinor, 50000);
      expect(restored.preferences.planningWeekday, DateTime.friday);
      expect(
        restored.scenarios.single.steps.first.parameters['period'],
        'week',
      );
      expect(restored.scenarios.single.updatedAt, at);
      expect(restored.scenarios.single.version, 1);
    },
  );

  test(
    'resetting learned personalization preserves confirmed preferences and scenarios',
    () async {
      final repo = MemoryRepository(file: file);
      await repo.load();
      repo.memory.observe('кофе', 'cafe', at: at);
      await repo.setPreferences(AssistantPreferences(primaryAccountId: 'cash'));
      await repo.saveScenario(scenario());
      await FinoraAi(memory: repo).resetPersonalization();
      final reopened = MemoryRepository(file: file);
      await reopened.load();
      expect(reopened.memory.merchants, isEmpty);
      expect(reopened.memory.preferences.primaryAccountId, 'cash');
      expect(reopened.memory.scenarios.single.id, 'weekly-review');
    },
  );

  test(
    'concurrent confirmed writes are serialized without losing fields or scenarios',
    () async {
      final repo = MemoryRepository(file: file);
      await repo.load();
      repo.memory.observe('кофе', 'cafe', at: at);
      await Future.wait([
        repo.setPreferences(AssistantPreferences(primaryAccountId: 'cash')),
        repo.saveScenario(scenario('one')),
        repo.saveScenario(scenario('two')),
      ]);
      final reopened = MemoryRepository(file: file);
      await reopened.load();
      expect(reopened.memory.scenarios.map((s) => s.id).toSet(), {
        'one',
        'two',
      });
      expect(reopened.memory.preferences.primaryAccountId, 'cash');
      expect(reopened.memory.categoryFor('кофе')?.categoryId, 'cafe');
    },
  );

  test(
    'scenario upsert and delete are durable and never remove unrelated memory',
    () async {
      final repo = MemoryRepository(file: file);
      await repo.load();
      repo.memory.observe('аптека', 'health', at: at);
      await repo.setPreferences(AssistantPreferences(primaryAccountId: 'cash'));
      await repo.saveScenario(scenario());
      await repo.saveScenario(
        scenario().copyWith(
          name: 'Обновлённый разбор',
          updatedAt: at.add(const Duration(days: 1)),
        ),
      );
      expect(repo.memory.scenarios, hasLength(1));
      expect(repo.memory.scenarios.single.name, 'Обновлённый разбор');
      await repo.deleteScenario('weekly-review');
      final reopened = MemoryRepository(file: file);
      await reopened.load();
      expect(reopened.memory.scenarios, isEmpty);
      expect(reopened.memory.categoryFor('аптека')?.categoryId, 'health');
      expect(reopened.memory.preferences.primaryAccountId, 'cash');
    },
  );

  test(
    'unknown commands, executable parameters and floating money are rejected',
    () {
      for (final step in [
        {
          'type': 'shell',
          'parameters': {'code': 'rm -rf /'},
        },
        {
          'type': 'debtPlan',
          'parameters': {'budgetMinor': 99.5},
        },
        {
          'type': 'showEntries',
          'parameters': {'sql': 'DELETE FROM entries'},
        },
        {
          'type': 'summary',
          'parameters': {'period': 'forever'},
        },
        {
          'type': 'upcomingPayments',
          'parameters': {'withinDays': 1000},
        },
      ]) {
        expect(() => ScenarioStep.fromJson(step), throwsFormatException);
      }
      expect(
        () => AssistantPreferences.fromJson({'planningWeekday': '5'}),
        throwsFormatException,
      );
      expect(
        () => AssistantPreferences(planningWeekday: 8),
        throwsFormatException,
      );
      expect(() => PlannerPreferences(budgetMinor: -1), throwsFormatException);
      expect(() => PlannerPreferences(reserveMinor: -1), throwsFormatException);
    },
  );

  test(
    'scenarios contain supported parameters, never stale observed balances or autoexecution',
    () {
      final json = scenario().toJson();
      expect(
        json.keys,
        unorderedEquals([
          'id',
          'name',
          'steps',
          'requiredData',
          'version',
          'updatedAt',
        ]),
      );
      expect(jsonEncode(json), isNot(contains('balance')));
      expect(
        () => ScenarioStep(
          type: ScenarioStepType.debtPlan,
          parameters: {'lastBalanceMinor': 50000},
        ),
        throwsFormatException,
      );
      expect(
        () => SavedAssistantScenario.fromJson({...json, 'schedule': 'daily'}),
        throwsFormatException,
      );
      expect(
        () => SavedAssistantScenario.fromJson({...json, 'version': 2}),
        throwsFormatException,
      );
      expect(
        () =>
            scenario().steps.add(ScenarioStep(type: ScenarioStepType.summary)),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'write failure is reported and keeps last committed bytes and in-memory preferences',
    () async {
      final repo = MemoryRepository(file: file);
      await repo.setPreferences(AssistantPreferences(primaryAccountId: 'old'));
      final committed = await file.readAsString();
      await Directory('${file.path}.tmp').create();
      await expectLater(
        repo.setPreferences(AssistantPreferences(primaryAccountId: 'new')),
        throwsA(isA<FileSystemException>()),
      );
      expect(await file.readAsString(), committed);
      expect(repo.memory.preferences.primaryAccountId, 'old');
      await expectLater(
        repo.saveScenario(scenario()),
        throwsA(isA<FileSystemException>()),
      );
      expect(repo.memory.scenarios, isEmpty);
    },
  );

  test(
    'invalid persisted scenario does not erase the original file or accept later silent overwrite',
    () async {
      final original = jsonEncode({
        'version': 4,
        'scenarios': [
          {
            'id': 'bad',
            'name': 'bad',
            'steps': [
              {'type': 'shell'},
            ],
            'updatedAt': at.toIso8601String(),
          },
        ],
      });
      await file.writeAsString(original);
      final repo = MemoryRepository(file: file);
      await repo.load();
      expect(repo.readError, isNotNull);
      await expectLater(
        repo.setPreferences(AssistantPreferences()),
        throwsFormatException,
      );
      expect(await file.readAsString(), original);
      // Explicit reset/restore is the only operation allowed to replace it.
      await repo.replace(PersonalMemory());
      expect(repo.readError, isNull);
      expect(
        jsonDecode(await file.readAsString())['version'],
        PersonalMemory.version,
      );
    },
  );

  test(
    'removing a model directory cannot remove memory, preferences or saved scenarios',
    () async {
      final repo = MemoryRepository(file: file);
      await repo.setPreferences(AssistantPreferences(primaryAccountId: 'cash'));
      await repo.saveScenario(scenario());
      final model = Directory('${dir.path}/finora_local_models');
      await model.create();
      await File('${model.path}/weights.bin').writeAsString('synthetic');
      await model.delete(recursive: true);
      final reopened = MemoryRepository(file: file);
      await reopened.load();
      expect(reopened.memory.preferences.primaryAccountId, 'cash');
      expect(reopened.memory.scenarios.single.id, 'weekly-review');
    },
  );

  testWidgets(
    'preferences editor works on a small phone and saves only explicit confirmation',
    (tester) async {
      sqfliteFfiInit();
      final finance = await tester.runAsync(
        () => FinanceRepository.open(
          factory: databaseFactoryFfi,
          path: '${dir.path}/finance.db',
        ),
      );
      final data = createDemoData(at);
      await tester.runAsync(() => finance!.save(data));
      final controller = FinanceController(finance!, _Quiet(), data);
      final memory = MemoryRepository(file: file);
      await tester.runAsync(memory.load);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        FinanceScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.app(Brightness.light, 'tropic'),
            home: AssistantMemoryScreen(repository: memory),
          ),
        ),
      );
      for (
        var i = 0;
        i < 20 && find.text('Изменить предпочтения').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.tap(find.text('Изменить предпочтения'));
      await tester.pumpAndSettle();
      expect(find.text('Подтверждённые предпочтения'), findsWidgets);
      expect(
        memory.memory.preferences.reportFormat,
        AssistantReportFormat.brief,
      );
      await tester.tap(find.text('Краткий'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Подробный').last);
      await tester.pumpAndSettle();
      expect(
        memory.memory.preferences.reportFormat,
        AssistantReportFormat.brief,
      );
      await tester.tap(find.text('Подтвердить и сохранить'));
      await tester.pumpAndSettle();
      for (
        var i = 0;
        i < 20 &&
            memory.memory.preferences.reportFormat !=
                AssistantReportFormat.detailed;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(
        memory.memory.preferences.reportFormat,
        AssistantReportFormat.detailed,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      memory.dispose();
      await tester.runAsync(finance.close);
    },
  );
}
