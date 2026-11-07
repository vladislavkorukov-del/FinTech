import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/main.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/i18n.dart';
import 'package:finora/presentation/screens/management.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

/// Finora 1.28: swipe to delete, money tips, other currencies, languages.
void main() {
  sqfliteFfiInit();
  late Directory dir;
  late FinanceRepository repository;
  late FinanceController controller;

  test('settings round trip; no currency view or name listening', () {
    const p = AppPreferences();
    final back = AppPreferences.fromJson(p.toJson());
    expect(back.tips, isTrue);
    expect(back.language, 'ru');
    expect(p.toJson().containsKey('displayCurrency'), isFalse);
    expect(p.toJson().containsKey('wakeWord'), isFalse);
    // Settings saved by 1.27/1.28 still load.
    final old = AppPreferences.fromJson({
      ...p.toJson(),
      'wakeWord': true,
      'displayCurrency': 'USD',
      'rates': {'USD': 90},
    });
    expect(old.language, 'ru');
  });

  test('English for the main labels, Russian otherwise', () {
    AppLanguage.code = 'en';
    addTearDown(() => AppLanguage.code = 'ru');
    expect(tr('Главная'), 'Home');
    expect(tr('Сохранить операцию'), 'Save transaction');
    expect(tr('Слово без перевода'), 'Слово без перевода');
    AppLanguage.code = 'ru';
    expect(tr('Главная'), 'Главная');
  });

  group('app', () {
    setUp(() async {
      await initializeDateFormatting('ru');
      await initializeDateFormatting('en');
      FlutterSecureStorage.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('finora-v128-');
      repository = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/db',
      );
      await repository.save(
        const FinanceData(
          accounts: [Account(id: 'card', name: 'Карта', openingMinor: 9000000)],
          goals: [Goal(id: 'car', name: 'Машина', targetMinor: 200000000)],
          members: [Member(id: 'me', name: 'Я')],
          demo: false,
        ),
      );
      controller = FinanceController(
        repository,
        _Quiet(),
        await repository.load(),
      );
    });
    tearDown(() async {
      controller.dispose();
      await repository.close();
      await dir.delete(recursive: true);
    });

    Future<void> flush(WidgetTester tester, bool Function() done) async {
      for (var i = 0; i < 60 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    Future<void> start(WidgetTester tester, [Widget? home]) async {
      tester.view.physicalSize = const Size(420, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        home == null
            ? FinoraApp(controller: controller, requireDeviceSecurity: false)
            : FinanceScope(
                controller: controller,
                child: MaterialApp(home: home),
              ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('swipe a dream left, Finora asks, it is gone', (tester) async {
      await start(tester, const GoalsScreen());
      final card = find.byKey(const ValueKey('swipe-goal-car'));
      await tester.drag(card, const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('finora-confirm')), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(controller.data.goals, hasLength(1));
      await tester.drag(card, const Offset(-600, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('finora-confirm-yes')));
      await flush(tester, () => controller.data.goals.isEmpty);
      expect(controller.data.goals, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('money tips: next tip, swipe away, back in settings', (
      tester,
    ) async {
      await start(tester);
      final tips = find.byKey(const ValueKey('money-tips'));
      await tester.scrollUntilVisible(
        tips,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      // 1.44: the achievements card is above; bring the tips fully into view.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('ФИНАНСОВАЯ ГРАМОТНОСТЬ'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('money-tips-next')));
      await tester.pumpAndSettle();
      await tester.drag(tips, const Offset(-600, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('finora-confirm-yes')));
      await flush(tester, () => !controller.data.preferences.tips);
      expect(controller.data.preferences.tips, isFalse);
      expect(find.byKey(const ValueKey('money-tips')), findsNothing);
    });

    testWidgets('1.29: tapping the balance opens the accounts again', (
      tester,
    ) async {
      await start(tester);
      await tester.tap(find.byKey(const ValueKey('header-balance')));
      await tester.pumpAndSettle();
      expect(find.byType(AccountsScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('currency-sheet')), findsNothing);
    });

    testWidgets('1.30: the tips card is the last block by default', (
      tester,
    ) async {
      // Even if an earlier order put it near the top.
      await tester.runAsync(
        () => controller.preferences(
          controller.data.preferences.copyWith(
            dashboardOrder: const ['summary', 'tips', 'accounts', 'goals'],
          ),
        ),
      );
      await start(tester);
      // A very tall screen: every block is built at once.
      tester.view.physicalSize = const Size(420, 6000);
      await tester.pumpAndSettle();
      final tips = find.byKey(const ValueKey('money-tips'));
      final scroll = find.byType(Scrollable).first;
      final goal = find.byKey(const ValueKey('swipe-dash-goal-car'));
      expect(goal, findsOneWidget);
      expect(tester.getTopLeft(goal).dy, lessThan(tester.getTopLeft(tips).dy));
      // Nothing else below it.
      await tester.drag(scroll, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(tips, findsOneWidget);
    });

    testWidgets('English labels after choosing the language', (tester) async {
      await tester.runAsync(
        () => controller.preferences(
          controller.data.preferences.copyWith(language: 'en'),
        ),
      );
      await start(tester);
      expect(find.text('Home'), findsWidgets);
      expect(find.text('More'), findsOneWidget);
      AppLanguage.code = 'ru';
    });
  });
}
