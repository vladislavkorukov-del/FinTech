import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/main.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/transactions.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/presentation/widgets/charts.dart';
import 'package:finora/presentation/widgets/common.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late FinanceRepository repository;
  late FinanceController controller;
  setUp(() async {
    await initializeDateFormatting('ru');
    FinanceFormat.numberPattern = 'space_comma';
    temp = await Directory.systemTemp.createTemp('finora-v11-dashboard-');
    repository = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${temp.path}/db',
    );
    final fixture = FinanceData(
      accounts: List.generate(
        6,
        (i) => Account(
          id: 'account$i',
          name: 'Счёт номер $i',
          openingMinor: 100000 + i * 10000,
          excluded: i == 4,
          archived: i == 5,
        ),
      ),
      categories: const [
        Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
      ],
      members: const [Member(id: 'me', name: 'Я')],
      preferences: const AppPreferences(theme: 'light'),
      demo: false,
    );
    await repository.save(fixture);
    controller = FinanceController(
      repository,
      _Quiet(),
      await repository.load(),
    );
  });
  tearDown(() async {
    controller.dispose();
    await repository.close();
    await temp.delete(recursive: true);
  });

  testWidgets(
    'all active accounts form one vertical list, including excluded ones',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        FinoraApp(controller: controller, requireDeviceSecurity: false),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tester.scrollUntilVisible(
          find.text('Счёт номер $i'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Счёт номер $i'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('Счёт номер 4'));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionsScreen), findsOneWidget);
      expect(
        tester
            .widget<TransactionsScreen>(find.byType(TransactionsScreen))
            .accountId,
        'account4',
      );
    },
  );
  testWidgets(
    'archived accounts expand independently of dashboard scroll state',
    (tester) async {
      await tester.pumpWidget(
        FinoraApp(controller: controller, requireDeviceSecurity: false),
      );
      await tester.pumpAndSettle();
      final header = find.text('Архивные счета · 1');
      await tester.scrollUntilVisible(
        header,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // 1.14: accounts form one draggable block, built as a whole.
      await tester.ensureVisible(header);
      await tester.pumpAndSettle();
      await tester.tap(header);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Счёт номер 5'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Счёт номер 5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('account settings button opens a real editor', (tester) async {
    await tester.pumpWidget(
      FinoraApp(controller: controller, requireDeviceSecurity: false),
    );
    await tester.pumpAndSettle();
    final button = find.byTooltip('Настроить счёт Счёт номер 0');
    await tester.scrollUntilVisible(
      button,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Настройка счёта'), findsOneWidget);
    expect(find.text('Начальный баланс'), findsOneWidget);
  });
  testWidgets(
    'dashboard action buttons are enabled and income card opens filtered history',
    (tester) async {
      await tester.pumpWidget(
        FinoraApp(controller: controller, requireDeviceSecurity: false),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is ButtonStyleButton && w.onPressed == null,
        ),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.text('Доходы'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Доходы'));
      await tester.pumpAndSettle();
      final page = tester.widget<TransactionsScreen>(
        find.byType(TransactionsScreen),
      );
      expect(page.initialKind, EntryKind.income);
      expect(page.initialRange, isNotNull);
    },
  );
  testWidgets(
    'daily columns expose exact sums, zero days, and a working day action',
    (tester) async {
      DateTime? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light, 'lime'),
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: DailyExpenseChart(
              start: DateTime(2026, 11),
              days: 3,
              amountsMinor: const {0: 12345, 2: 70000},
              currency: 'RUB',
              onDayTap: (d) => selected = d,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(money(12345)), findsOneWidget);
      expect(find.text(money(0)), findsOneWidget);
      expect(find.text(money(70000)), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('daily-bar-1')));
      await tester.pumpAndSettle();
      expect(selected, DateTime(2026, 11, 2));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('daily labels stay visible with large text at 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: DailyExpenseChart(
              start: DateTime(2026, 11),
              days: 31,
              amountsMinor: const {0: 12345},
              currency: 'RUB',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(money(12345)), findsOneWidget);
    expect(find.text('••••••'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
