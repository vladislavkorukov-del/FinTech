import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/finance_engine.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/entry_editor.dart';
import 'package:finora/presentation/screens/management.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/presentation/widgets/common.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _SilentNotifications extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late FinanceRepository repository;
  late FinanceController controller;
  final future = DateTime(DateTime.now().year + 1, 3, 10);

  FinanceData fixture() => FinanceData(
    accounts: const [
      Account(id: 'cash', name: 'На каждый день', openingMinor: 1000000),
    ],
    categories: const [
      Category(id: 'services', name: 'Сервисы', kind: EntryKind.expense),
      Category(id: 'salary', name: 'Зарплата', kind: EntryKind.income),
    ],
    members: const [Member(id: 'me', name: 'Я')],
    goals: const [
      Goal(
        id: 'sea',
        name: 'Поездка к морю',
        targetMinor: 100000,
        savedMinor: 10000,
      ),
    ],
    recurring: [
      RecurringRule(
        id: 'music',
        name: 'Музыка без рекламы',
        accountId: 'cash',
        categoryId: 'services',
        amountMinor: 39900,
        nextDate: future,
        paymentType: 'subscription',
      ),
      RecurringRule(
        id: 'rent',
        name: 'Аренда квартиры',
        accountId: 'cash',
        categoryId: 'services',
        amountMinor: 500000,
        nextDate: future,
        paymentType: 'mandatory',
      ),
      RecurringRule(
        id: 'salary',
        name: 'Моя зарплата',
        accountId: 'cash',
        categoryId: 'salary',
        amountMinor: 900000,
        nextDate: future,
        kind: EntryKind.income,
      ),
    ],
  );

  setUp(() async {
    await initializeDateFormatting('ru');
    FinanceFormat.numberPattern = 'space_comma';
    directory = await Directory.systemTemp.createTemp('finora-goal-ui-');
    repository = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/finance.db',
    );
    await repository.save(fixture());
    controller = FinanceController(
      repository,
      _SilentNotifications(),
      await repository.load(),
    );
  });
  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    double textScale = 1,
    Size size = const Size(400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FinanceScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light, 'lime'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('ru')],
          locale: const Locale('ru'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> commit(
    WidgetTester tester,
    Finder button,
    bool Function() ready,
  ) async {
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(button);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!ready()) {
        if (DateTime.now().isAfter(deadline)) {
          throw TestFailure('Financial operation was not committed');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'dream contribution opens real transfer, persists it and conserves funds',
    (tester) async {
      await mount(tester, const GoalsScreen());
      await tester.ensureVisible(find.text('Пополнить мечту'));
      await tester.tap(find.text('Пополнить мечту'));
      await tester.pumpAndSettle();
      expect(find.byType(EntryEditor), findsOneWidget);
      expect(
        tester.widget<EntryEditor>(find.byType(EntryEditor)).goalId,
        'sea',
      );
      expect(
        tester.widget<EntryEditor>(find.byType(EntryEditor)).kind,
        EntryKind.transfer,
      );
      await tester.tap(find.byTooltip('Системная клавиатура'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '125');
      final save = find.text('Сохранить операцию');
      await tester.scrollUntilVisible(
        save,
        300,
        scrollable: find
            .descendant(
              of: find.byType(EntryEditor),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await commit(tester, save, () => controller.data.entries.isNotEmpty);
      final entry = controller.data.entries.single;
      expect(entry.toGoalId, 'sea');
      expect(entry.toAccountId, isNull);
      expect(entry.kind, EntryKind.transfer);
      expect(entry.amountMinor, 12500);
      expect(
        FinanceEngine.balance(
          controller.data.accounts.single,
          controller.data.entries,
        ),
        987500,
      );
      expect(
        FinanceEngine.goalSaved(
          controller.data.goals.single,
          controller.data.entries,
        ),
        22500,
      );
      expect(controller.data.goals.single.savedMinor, 10000);
      expect(controller.balance, 1000000);
      final loaded = await tester.runAsync(repository.load);
      expect(loaded!.entries.single.toGoalId, 'sea');
      expect(find.text('225 ₽'), findsOneWidget);
    },
  );

  testWidgets(
    'goal progress includes posted transfers, initial reserve stays initial and deletion is guarded',
    (tester) async {
      final now = DateTime.now();
      await tester.runAsync(
        () => controller.saveEntry(
          FinanceEntry(
            id: 'posted',
            kind: EntryKind.transfer,
            amountMinor: 20000,
            currency: 'RUB',
            accountId: 'cash',
            toGoalId: 'sea',
            date: now,
          ),
        ),
      );
      await tester.runAsync(
        () => controller.saveEntry(
          FinanceEntry(
            id: 'pending',
            kind: EntryKind.transfer,
            amountMinor: 70000,
            currency: 'RUB',
            accountId: 'cash',
            toGoalId: 'sea',
            date: now,
            status: 'pending',
          ),
        ),
      );
      await mount(tester, const GoalsScreen());
      expect(find.text('300 ₽'), findsOneWidget);
      expect(find.text('30% накоплено'), findsOneWidget);
      await tester.tap(find.text('Поездка к морю'));
      await tester.pumpAndSettle();
      expect(find.text('Начальный резерв'), findsOneWidget);
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(fields[2].controller!.text, '100.00');
      await tester.scrollUntilVisible(
        find.text('Удалить'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Продолжить'));
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      // The mutation is queued behind real SQLite work. Alternate frame and
      // platform microtask turns before waiting for finite UI animations.
      for (
        var attempt = 0;
        attempt < 30 &&
            find.textContaining('В мечте есть переводы.').evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(find.textContaining('В мечте есть переводы.'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(controller.data.goals, hasLength(1));
      expect(controller.data.entries, hasLength(2));
    },
  );

  testWidgets(
    'subscriptions, mandatory payments and incomes have independent filters',
    (tester) async {
      await mount(
        tester,
        const RecurringScreen(initialPaymentType: 'subscription'),
      );
      expect(find.byKey(const ValueKey('payment-rule-music')), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-rule-rent')), findsNothing);
      expect(find.byKey(const ValueKey('payment-rule-salary')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('payment-filter-mandatory')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('payment-rule-rent')), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-rule-music')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('payment-filter-income')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('payment-rule-salary')), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-rule-rent')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new subscription saves actual weekly payment with selected classification',
    (tester) async {
      await mount(
        tester,
        const RecurringScreen(initialPaymentType: 'subscription'),
      );
      await tester.tap(find.byTooltip('Добавить подписку'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Мой новый сервис',
      );
      await tester.enterText(find.byType(TextFormField).at(1), '290');
      await tester.ensureVisible(find.text('Ежемесячно'));
      await tester.tap(find.text('Ежемесячно'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Еженедельно').last);
      await tester.pumpAndSettle();
      final save = find.text('Сохранить');
      await tester.scrollUntilVisible(
        save,
        300,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await commit(tester, save, () => controller.data.recurring.length == 4);
      final created = controller.data.recurring.singleWhere(
        (r) => r.name == 'Мой новый сервис',
      );
      expect(created.amountMinor, 29000);
      expect(created.paymentType, 'subscription');
      expect(created.frequency, 'weekly');
      expect(created.kind, EntryKind.expense);
      final loaded = await tester.runAsync(repository.load);
      expect(
        loaded!.recurring.singleWhere((r) => r.id == created.id).paymentType,
        'subscription',
      );
    },
  );

  testWidgets(
    'regular income creation cannot be classified as a subscription',
    (tester) async {
      await mount(tester, const RecurringScreen());
      await tester.tap(find.byKey(const ValueKey('payment-filter-income')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Добавить регулярный доход'));
      await tester.pumpAndSettle();
      expect(find.text('Вид платежа'), findsNothing);
      expect(find.byKey(const ValueKey('service-picker')), findsNothing);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Проценты по вкладу',
      );
      await tester.enterText(find.byType(TextFormField).at(1), '1000');
      final save = find.text('Сохранить');
      await tester.scrollUntilVisible(
        save,
        300,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await commit(tester, save, () => controller.data.recurring.length == 4);
      final created = controller.data.recurring.singleWhere(
        (r) => r.name == 'Проценты по вкладу',
      );
      expect(created.kind, EntryKind.income);
      expect(created.paymentType, 'mandatory');
      expect(created.categoryId, 'salary');
    },
  );

  testWidgets(
    'editing subscription classification moves the persisted rule to mandatory payments',
    (tester) async {
      await mount(
        tester,
        const RecurringScreen(initialPaymentType: 'subscription'),
      );
      await tester.tap(find.byKey(const ValueKey('payment-rule-music')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Подписка'));
      await tester.tap(find.text('Подписка'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Обязательный платёж').last);
      await tester.pumpAndSettle();
      final save = find.text('Сохранить');
      await tester.scrollUntilVisible(
        save,
        300,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await commit(
        tester,
        save,
        () =>
            controller.data.recurring
                .singleWhere((r) => r.id == 'music')
                .paymentType ==
            'mandatory',
      );
      expect(find.byKey(const ValueKey('payment-rule-music')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('payment-filter-mandatory')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('payment-rule-music')), findsOneWidget);
      final loaded = await tester.runAsync(repository.load);
      expect(
        loaded!.recurring.singleWhere((r) => r.id == 'music').paymentType,
        'mandatory',
      );
    },
  );

  for (final page in [const GoalsScreen(), const RecurringScreen()]) {
    testWidgets('${page.runtimeType} fits 320px with large text', (
      tester,
    ) async {
      await mount(tester, page, size: const Size(320, 640), textScale: 1.5);
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 7; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -220));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
