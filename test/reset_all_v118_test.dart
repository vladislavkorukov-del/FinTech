import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/settings.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

/// Finance 1.18: «Сбросить всё» at the top of Settings erases the person's
/// data after typing «СБРОС»; appearance stays, categories return to the
/// standard set, the demo is not seeded again.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late Directory dir;
  late FinanceRepository repository;
  late FinanceController controller;

  const theme = 'light';
  const accent = 'midnight';
  setUp(() async {
    await initializeDateFormatting('ru');
    FlutterSecureStorage.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('finora-v118-reset-');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      paths,
      (call) async => dir.path,
    );
    repository = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/db',
    );
    await repository.save(
      FinanceData(
        accounts: const [Account(id: 'a', name: 'Карта', openingMinor: 100000)],
        categories: const [
          Category(id: 'mine', name: 'Моя', kind: EntryKind.expense),
        ],
        entries: [
          FinanceEntry(
            id: 'e',
            kind: EntryKind.expense,
            amountMinor: 5000,
            currency: 'RUB',
            accountId: 'a',
            categoryId: 'mine',
            date: DateTime(2026, 11, 1),
            payee: 'Пятёрочка',
          ),
        ],
        goals: const [Goal(id: 'g', name: 'Отпуск', targetMinor: 100000)],
        members: const [
          Member(id: 'me', name: 'Я'),
          Member(id: 'wife', name: 'Жена'),
        ],
        preferences: const AppPreferences(
          theme: theme,
          accent: accent,
          dashboardOrder: ['recent'],
          accountOrder: ['a'],
        ),
        demo: false,
      ),
    );
    controller = FinanceController(
      repository,
      _Quiet(),
      await repository.load(),
    );
    for (final name in ['receipts', 'service_icons']) {
      final folder = await Directory('${dir.path}/$name').create();
      await File('${folder.path}/x.png').writeAsBytes([1, 2, 3]);
    }
  });
  tearDown(() async {
    controller.dispose();
    await repository.close();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(paths, null);
    await dir.delete(recursive: true);
  });

  void expectReset(FinanceData d) {
    expect(d.entries, isEmpty);
    expect(d.accounts, isEmpty);
    expect(d.goals, isEmpty);
    expect(d.budgets, isEmpty);
    expect(d.recurring, isEmpty);
    expect(d.members.map((m) => m.name), ['Я']);
    expect(
      d.categories.map((c) => c.name),
      containsAll(['Продукты', 'Транспорт', 'Зарплата']),
    );
    expect(d.categories.any((c) => c.name == 'Моя'), isFalse);
    expect(d.preferences.theme, theme);
    expect(d.preferences.accent, accent);
    expect(d.preferences.dashboardOrder, isEmpty);
    expect(d.demo, isFalse);
  }

  test(
    'repository reset keeps appearance and does not reseed the demo',
    () async {
      await repository.resetAll();
      expectReset(await repository.load());
      await repository.close();
      repository = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/db',
      );
      final reopened = await repository.load();
      expectReset(reopened);
    },
  );

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinanceScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.app(Brightness.light, accent),
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> flush(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 150 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('settings open the account import', (tester) async {
    await mount(tester);
    final item = find.text('Перенести счета со скриншота');
    await tester.scrollUntilVisible(
      item,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(item);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(item);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Перенос счетов'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('1.26: reset is a quiet row; a swipe confirms it, no message', (
    tester,
  ) async {
    await mount(tester);
    final row = find.byKey(const ValueKey('reset-all'));
    await tester.scrollUntilVisible(
      row,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Cancel changes nothing.
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('reset-sheet')), findsOneWidget);
    expect(find.text('Проведите, чтобы сбросить'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.data.entries, hasLength(1));

    // A short swipe springs back and does nothing.
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 500));
    final knob = find.byKey(const ValueKey('swipe-knob'));
    await tester.drag(knob, const Offset(120, 0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('reset-sheet')), findsOneWidget);
    expect(controller.data.entries, hasLength(1));

    // All the way: reset.
    await tester.drag(knob, const Offset(600, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await flush(
      tester,
      () =>
          controller.data.entries.isEmpty &&
          !Directory('${dir.path}/receipts').existsSync() &&
          !Directory('${dir.path}/service_icons').existsSync(),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Все данные сброшены.'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expectReset(controller.data);
    expectReset((await tester.runAsync(repository.load))!);
    for (final name in ['receipts', 'service_icons']) {
      expect(
        Directory('${dir.path}/$name').existsSync(),
        isFalse,
        reason: name,
      );
    }
    expect(File('${dir.path}/db').existsSync(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('1.26: settings are grouped into pages; backups are inside', (
    tester,
  ) async {
    await mount(tester);
    for (final key in [
      'settings-profile',
      'settings-appearance',
      'settings-general',
      'settings-notifications',
      'settings-security',
      'settings-backups',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    // No backup buttons on the first page.
    expect(find.text('Полная копия'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settings-backups')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Резервные копии'), findsOneWidget);
    expect(find.text('Полная копия'), findsOneWidget);
    expect(find.text('Из снимка базы'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
