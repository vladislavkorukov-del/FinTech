import 'dart:io';

import 'package:finora/data/demo_data.dart';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/main.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/entry_editor.dart';
import 'package:finora/presentation/screens/management.dart';
import 'package:finora/presentation/screens/settings.dart';
import 'package:finora/presentation/screens/transactions.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

/// Finance 1.23: commands through the voice orb.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const voice = MethodChannel('finora/voice');
  late Directory dir;
  late FinanceRepository repository;
  late FinanceController controller;
  late List<String> heard;
  var calls = 0;
  setUp(() async {
    await initializeDateFormatting('ru');
    FlutterSecureStorage.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('finora-v123-voice-');
    repository = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/db',
    );
    await repository.save(
      FinanceData(
        accounts: const [Account(id: 'card', name: 'Карта')],
        entries: [
          for (final (id, day, amount, kind) in [
            ('a', 3, 120000, EntryKind.expense),
            ('b', 20, 30050, EntryKind.expense),
            ('c', 10, 9000000, EntryKind.income),
          ])
            FinanceEntry(
              id: id,
              kind: kind,
              amountMinor: amount,
              currency: 'RUB',
              accountId: 'card',
              categoryId: kind == EntryKind.income ? 'income-0' : 'expense-0',
              date: DateTime(2026, 6, day),
            ),
          FinanceEntry(
            id: 'd',
            kind: EntryKind.expense,
            amountMinor: 77700,
            currency: 'RUB',
            accountId: 'card',
            categoryId: 'expense-0',
            date: DateTime(2026, 7, 2),
          ),
        ],
        categories: createDemoData(DateTime(2026, 11, 6)).categories,
        members: const [Member(id: 'me', name: 'Я')],
        demo: false,
      ),
    );
    controller = FinanceController(
      repository,
      _Quiet(),
      await repository.load(),
    );
    heard = ['пятерочка 450 рублей', 'пятерочка 450'];
    calls = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(voice, (
      call,
    ) async {
      if (call.method == 'listen') {
        calls++;
        return heard;
      }
      return true;
    });
  });
  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(voice, null);
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
  }

  Future<void> say(WidgetTester tester, List<String> phrase) async {
    heard = phrase;
    final before = calls;
    await tester.tap(find.byKey(const ValueKey('nav-voice')));
    await flush(tester, () => calls > before);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinoraApp(controller: controller, requireDeviceSecurity: false),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('«покажи расходы за июнь» lists June expenses with a total', (
    tester,
  ) async {
    await start(tester);
    await say(tester, ['покажи расходы за июнь 2026']);
    expect(find.byType(TransactionsScreen), findsOneWidget);
    expect(find.text('Расходы · июнь 2026'), findsOneWidget);
    final count = tester.widget<Text>(
      find.byKey(const ValueKey('transactions-count')),
    );
    expect(count.data, startsWith('2 операций · '));
    expect(count.data!.replaceAll(RegExp(r'\s'), ''), contains('1500,5₽'));
    expect(controller.data.entries, hasLength(4));
    await back(tester);
    await say(tester, ['покажи доход за 2026 год']);
    expect(find.text('Доходы · 2026 год'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('transactions-count')))
          .data,
      startsWith('1 операций'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme, screens and tabs by voice', (tester) async {
    await start(tester);
    final accent = controller.data.preferences.accent;
    await say(tester, ['поменяй тему на зелёную']);
    await flush(tester, () => controller.data.preferences.accent != accent);
    final green = controller.data.preferences.accent;
    expect(green, anyOf('forest', 'emerald'));
    expect(find.textContaining('Тема: '), findsOneWidget);
    await say(tester, ['включи светлую тему']);
    await flush(tester, () => controller.data.preferences.theme == 'light');
    expect(controller.data.preferences.theme, 'light');
    expect(controller.data.preferences.accent, green);

    await say(tester, ['открой настройки']);
    expect(find.byType(SettingsScreen), findsOneWidget);
    await back(tester);
    await say(tester, ['мои цели']);
    expect(find.byType(GoalsScreen), findsOneWidget);
    await back(tester);
    await say(tester, ['покажи операции']);
    expect(find.byType(TransactionsScreen), findsOneWidget);
    expect(find.text('Операции'), findsWidgets);
    await say(tester, ['покажи что-нибудь интересное']);
    expect(find.textContaining('Не понял'), findsOneWidget);
    // An operation still opens the editor, filled, without listening twice.
    await say(tester, ['пятерочка 450 рублей']);
    expect(find.byType(EntryEditor), findsOneWidget);
    expect(calls, 7);
    expect(
      find.byWidgetPredicate(
        (w) => w is EditableText && w.controller.text == '450.00',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
