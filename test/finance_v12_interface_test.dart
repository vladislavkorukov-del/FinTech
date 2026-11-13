import 'dart:io';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/bank_catalog.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/presentation/screens/dashboard.dart';
import 'package:finora/presentation/screens/management.dart';
import 'package:finora/presentation/screens/analytics.dart';
import 'package:finora/presentation/screens/entry_editor.dart';
import 'package:finora/presentation/widgets/finance_header.dart';
import 'package:finora/presentation/widgets/category_orbit_chart.dart';
import 'package:finora/presentation/widgets/half_year_chart.dart';
import 'package:finora/presentation/widgets/common.dart';
import 'package:finora/presentation/widgets/amount_pad.dart';
import 'package:finora/presentation/widgets/service_badge.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late FinanceRepository repository;
  late FinanceController controller;
  setUp(() async {
    await initializeDateFormatting('ru');
    FlutterSecureStorage.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('finance-v12-ui-');
    repository = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/db',
    );
    const fixture = FinanceData(
      accounts: [Account(id: 'cash', name: 'Карта', openingMinor: 1000000)],
      categories: [
        Category(
          id: 'food',
          name: 'Продукты',
          kind: EntryKind.expense,
          icon: 0,
        ),
        Category(
          id: 'car',
          name: 'Автомобиль',
          kind: EntryKind.expense,
          icon: 3,
        ),
        Category(
          id: 'salary',
          name: 'Зарплата',
          kind: EntryKind.income,
          icon: 20,
        ),
      ],
      members: [Member(id: 'me', name: 'Я')],
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
    await directory.delete(recursive: true);
  });
  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    Size size = const Size(400, 900),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FinanceScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark, 'coffee'),
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> entry(
    WidgetTester tester,
    EntryKind kind, {
    FinanceEntry? existing,
  }) async {
    final context = tester.element(find.byType(Scaffold).first);
    showEntryEditor(context, kind: kind, entry: existing);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, bool Function() done) async {
    final button = find.text('Сохранить операцию');
    await tester.scrollUntilVisible(
      button,
      200,
      scrollable: find
          .descendant(
            of: find.byType(EntryEditor),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(button);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!done()) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Expected persisted operation was not observed');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
  }

  Future<void> amount(WidgetTester tester) async {
    for (final digit in ['5', '0']) {
      await tester.tap(
        find.descendant(of: find.byType(AmountPad), matching: find.text(digit)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'header shows centered total balance and currency instead of the F logo',
    (tester) async {
      for (final width in [320.0, 412.0]) {
        for (final scale in [1.0, 1.6]) {
          await mount(
            tester,
            const Scaffold(
              body: Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: FinanceHeader(),
              ),
            ),
            size: Size(width, 700),
            scale: scale,
          );
          final balance = find.byKey(const ValueKey('header-balance'));
          expect(tester.getCenter(balance).dx, closeTo(width / 2, .01));
          expect(
            find.text(money(controller.balance, controller.currency)),
            findsOneWidget,
          );
          // 1.58: no caption above the number.
          expect(
            find.text('Общий баланс · ${controller.currency}'),
            findsNothing,
          );
          expect(find.byType(FinanceBrand), findsNothing);
          expect(find.byType(Image), findsNothing);
          expect(find.byIcon(Icons.visibility_outlined), findsNothing);
          expect(tester.takeException(), isNull);
        }
      }
      // 1.57: the header shows only the balance; settings and the family
      // profile are reached from «Ещё».
      expect(find.byTooltip('Моя семья'), findsNothing);
      expect(find.byTooltip('Настройки'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('header-balance')));
      await tester.pumpAndSettle();
      expect(find.byType(AccountsScreen), findsOneWidget);
    },
  );
  for (final (size, scale) in [
    (const Size(320, 740), 1.4),
    (const Size(412, 900), 1.0),
    (const Size(740, 360), 1.0),
  ]) {
    testWidgets(
      'dashboard order, no duplicate balance and equal actions at ${size.width}x${size.height} text $scale',
      (tester) async {
        await mount(
          tester,
          Scaffold(
            body: Dashboard(onTransactions: () {}, onAnalytics: () {}),
          ),
          size: size,
          scale: scale,
        );
        double top(Finder f) => tester.getTopLeft(f).dy;
        final header = find.byKey(const ValueKey('header-balance'));
        final summary = find.byKey(const ValueKey('dashboard-month-summary'));
        final actions = find.byKey(const ValueKey('dashboard-actions'));
        expect(find.byKey(const ValueKey('dashboard-balance')), findsNothing);
        expect(find.text('Общий баланс'), findsNothing);
        // The total is shown once, in the header; account rows keep their
        // own balances.
        expect(
          find.descendant(
            of: header,
            matching: find.text(money(controller.balance, controller.currency)),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Общий баланс'), findsNothing);
        expect(find.bySemanticsLabel(RegExp('^Общий баланс')), findsOneWidget);
        expect(top(header), lessThan(top(summary)));
        expect(top(summary), lessThan(top(actions)));
        // Actions sit directly below the month income/expense cards.
        expect(
          top(actions) - tester.getBottomLeft(summary).dy,
          inInclusiveRange(0, 12),
        );
        await tester.scrollUntilVisible(
          find.text('Все счета'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(top(actions), lessThan(top(find.text('Все счета'))));
        final keys = [
          'quick-action-income',
          'quick-action-expense',
          'quick-action-transfer',
        ];
        await tester.scrollUntilVisible(
          actions,
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        final sizes = keys
            .map((k) => tester.getSize(find.byKey(ValueKey(k))))
            .toList();
        expect(sizes[0].width, closeTo(sizes[1].width, .01));
        expect(sizes[1].width, closeTo(sizes[2].width, .01));
        for (final size in sizes) {
          expect(size.height, greaterThanOrEqualTo(48));
        }
        expect(find.text('Мои финансы'), findsNothing);
        expect(find.text('Всё важное. В одном месте.'), findsNothing);
        expect(find.byTooltip('Скрыть суммы'), findsNothing);
        expect(tester.takeException(), isNull);
        for (final (key, kind) in [
          ('quick-action-income', EntryKind.income),
          ('quick-action-expense', EntryKind.expense),
          ('quick-action-transfer', EntryKind.transfer),
        ]) {
          await tester.tap(find.byKey(ValueKey(key)));
          await tester.pumpAndSettle();
          final editor = tester.widget<EntryEditor>(find.byType(EntryEditor));
          expect(editor.kind, kind);
          await tester.tap(find.byType(CloseButton));
          await tester.pumpAndSettle();
        }
      },
    );
  }
  testWidgets('account bank is picked from the Bank of Russia register', (
    tester,
  ) async {
    await mount(
      tester,
      const Scaffold(body: SizedBox()),
      size: const Size(320, 700),
      scale: 1.3,
    );
    final context = tester.element(find.byType(Scaffold).first);
    showAccountEditor(context);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('pick-bank')));
    await tester.tap(find.byKey(const ValueKey('pick-bank')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('bank-search')),
      'тинькофф',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bank-option-bank_2673')), findsOneWidget);
    expect(find.textContaining('рег. № 2673'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bank-option-bank_2673')));
    await tester.pumpAndSettle();
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('account-bank')),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.controller.text, 'Т-Банк');
    expect(tester.takeException(), isNull);
  });
  testWidgets('bank without a bundled original mark shows a neutral glyph', (
    tester,
  ) async {
    final bank = BankCatalog.entries.firstWhere((b) => b.logoAsset == null);
    await mount(
      tester,
      Scaffold(
        body: Center(child: ServiceBadge(serviceId: bank.id)),
      ),
    );
    expect(find.byIcon(Icons.account_balance_outlined), findsOneWidget);
    expect(find.byIcon(Icons.subscriptions_outlined), findsNothing);
    expect(find.byType(Image), findsNothing);
  });
  testWidgets(
    'last categories only learn committed new entries, independently and persist',
    (tester) async {
      await mount(tester, const Scaffold(body: SizedBox()));
      await entry(tester, EntryKind.expense);
      await amount(tester);
      await tester.tap(find.text('Продукты'));
      await save(tester, () => controller.data.entries.length == 1);
      expect(controller.data.preferences.lastExpenseCategoryId, 'food');
      expect(controller.data.preferences.lastIncomeCategoryId, isNull);
      await entry(tester, EntryKind.expense);
      expect(find.text('Последняя: Продукты'), findsOneWidget);
      final choices = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
      expect(choices.where((c) => c.selected), isEmpty);
      await tester.tap(find.byKey(const ValueKey('last-category')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .where((c) => c.selected),
        hasLength(1),
      );
      await tester.tap(find.text('Автомобиль'));
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(controller.data.preferences.lastExpenseCategoryId, 'food');
      await entry(tester, EntryKind.expense);
      await amount(tester);
      await tester.tap(find.text('Автомобиль'));
      await save(tester, () => controller.data.entries.length == 2);
      expect(controller.data.preferences.lastExpenseCategoryId, 'car');
      await entry(tester, EntryKind.income);
      expect(find.byKey(const ValueKey('last-category')), findsNothing);
      await amount(tester);
      await tester.tap(find.text('Зарплата'));
      await save(tester, () => controller.data.entries.length == 3);
      expect(controller.data.preferences.lastExpenseCategoryId, 'car');
      expect(controller.data.preferences.lastIncomeCategoryId, 'salary');
      await tester.runAsync(() async {
        await repository.close();
        repository = await FinanceRepository.open(
          factory: databaseFactoryFfi,
          path: '${directory.path}/db',
        );
      });
      final restored = await tester.runAsync(repository.load);
      expect(restored!.preferences.lastExpenseCategoryId, 'car');
      expect(restored.preferences.lastIncomeCategoryId, 'salary');
    },
  );
  testWidgets(
    'editing history and rejected new entry do not replace last categories',
    (tester) async {
      final old = FinanceEntry(
        id: 'old',
        kind: EntryKind.expense,
        amountMinor: 500,
        currency: 'RUB',
        accountId: 'cash',
        categoryId: 'food',
        date: DateTime.now(),
      );
      await tester.runAsync(
        () => controller.mutate(
          (d) => d.copyWith(
            entries: [old],
            preferences: d.preferences.copyWith(lastExpenseCategoryId: 'car'),
          ),
        ),
      );
      await mount(tester, const Scaffold(body: SizedBox()));
      await entry(tester, EntryKind.expense, existing: old);
      expect(find.byKey(const ValueKey('last-category')), findsNothing);
      await save(tester, () => controller.data.entries.single != old);
      expect(controller.data.preferences.lastExpenseCategoryId, 'car');
      await entry(tester, EntryKind.income);
      await tester.tap(find.text('Зарплата'));
      final saveButton = find.text('Сохранить операцию');
      await tester.scrollUntilVisible(
        saveButton,
        200,
        scrollable: find
            .descendant(
              of: find.byType(EntryEditor),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      expect(
        find.text('Введите сумму, не более двух знаков после запятой'),
        findsOneWidget,
      );
      expect(find.byType(EntryEditor), findsOneWidget);
      expect(controller.data.entries, hasLength(1));
      expect(controller.data.preferences.lastIncomeCategoryId, isNull);
      final stored = await tester.runAsync(repository.load);
      expect(stored!.preferences.lastExpenseCategoryId, 'car');
      expect(stored.preferences.lastIncomeCategoryId, isNull);
    },
  );
  testWidgets(
    'failed SQLite commit leaves ledger and quick category unchanged',
    (tester) async {
      await mount(tester, const Scaffold(body: SizedBox()));
      await entry(tester, EntryKind.expense);
      await amount(tester);
      await tester.tap(find.text('Продукты'));
      final saveButton = find.text('Сохранить операцию');
      await tester.scrollUntilVisible(
        saveButton,
        200,
        scrollable: find
            .descendant(
              of: find.byType(EntryEditor),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.runAsync(repository.close);
      final button = tester.widget<FilledButton>(
        find.ancestor(of: saveButton, matching: find.byType(FilledButton)),
      );
      // Await the real async handler outside the widget fake clock: SQLite FFI
      // runs on a real isolate, including its closed-database failure path.
      await tester.runAsync(button.onPressed! as Future<void> Function());
      await tester.pumpAndSettle();
      expect(find.byType(EntryEditor), findsOneWidget);
      expect(controller.data.entries, isEmpty);
      expect(controller.data.preferences.lastExpenseCategoryId, isNull);
      expect(find.byType(SnackBar), findsOneWidget);
      await tester.runAsync(() async {
        repository = await FinanceRepository.open(
          factory: databaseFactoryFfi,
          path: '${directory.path}/db',
        );
      });
      final restored = await tester.runAsync(repository.load);
      expect(restored!.entries, isEmpty);
      expect(restored.preferences.lastExpenseCategoryId, isNull);
    },
  );
  testWidgets(
    'history can edit archived account and category but new duplicate cannot use archive',
    (tester) async {
      final old = FinanceEntry(
        id: 'old',
        kind: EntryKind.expense,
        amountMinor: 500,
        currency: 'RUB',
        accountId: 'cash',
        categoryId: 'food',
        date: DateTime.now(),
      );
      await tester.runAsync(
        () => controller.mutate(
          (d) => d.copyWith(
            entries: [old],
            accounts: [d.accounts.single.copyWith(archived: true)],
          ),
        ),
      );
      await tester.runAsync(() => controller.deleteCategory('food'));
      await mount(tester, const Scaffold(body: SizedBox()));
      await entry(tester, EntryKind.expense, existing: old);
      expect(find.byType(EntryEditor), findsOneWidget);
      expect(find.text('Продукты'), findsOneWidget);
      await save(tester, () => controller.data.entries.single != old);
      await tester.runAsync(
        () => controller.mutate(
          (d) => d.copyWith(
            accounts: [d.accounts.single.copyWith(archived: false)],
          ),
        ),
      );
      await entry(
        tester,
        EntryKind.expense,
        existing: old.copyWith(id: 'copy'),
      );
      expect(find.text('Продукты'), findsNothing);
      expect(
        tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .where((c) => c.selected),
        isEmpty,
      );
      await tester.tap(find.text('Автомобиль'));
      await save(tester, () => controller.data.entries.length == 2);
      expect(
        controller.data.entries.firstWhere((e) => e.id == 'copy').categoryId,
        'car',
      );
      expect(controller.data.preferences.lastExpenseCategoryId, 'car');
    },
  );
  testWidgets(
    'archived last category disappears from quick choice while history stays',
    (tester) async {
      await tester.runAsync(
        () => controller.mutate(
          (d) => d.copyWith(
            entries: [
              FinanceEntry(
                id: 'spent',
                kind: EntryKind.expense,
                amountMinor: 500,
                currency: 'RUB',
                accountId: 'cash',
                categoryId: 'food',
                date: DateTime.now(),
              ),
            ],
            preferences: d.preferences.copyWith(lastExpenseCategoryId: 'food'),
          ),
        ),
      );
      await tester.runAsync(() => controller.deleteCategory('food'));
      expect(controller.category('food')!.archived, isTrue);
      expect(controller.data.entries.single.categoryId, 'food');
      expect(controller.data.preferences.lastExpenseCategoryId, isNull);
      await mount(tester, const Scaffold(body: SizedBox()));
      await entry(tester, EntryKind.expense);
      expect(find.text('Продукты'), findsNothing);
      expect(find.byKey(const ValueKey('last-category')), findsNothing);
    },
  );
  testWidgets('1.26 ring: period in the middle, branch only on tap, details', (
    tester,
  ) async {
    String? detail;
    const slices = [
      CategorySlice(
        id: 'a',
        name: 'Еда',
        icon: Icons.restaurant_outlined,
        color: Colors.orange,
        amount: 2500,
      ),
      CategorySlice(
        id: 'b',
        name: 'Дом',
        icon: Icons.home_outlined,
        color: Colors.blue,
        amount: 7500,
      ),
    ];
    await mount(
      tester,
      Scaffold(
        body: CategoryOrbitChart(
          title: 'Ноябрь',
          slices: slices,
          currency: 'RUB',
          onDetails: (s) => detail = s,
        ),
      ),
    );
    expect(find.text('Ноябрь'), findsOneWidget);
    expect(find.text(money(10000)), findsOneWidget);
    expect(find.text('2 категории'), findsOneWidget);
    // Icons sit on the sectors; no branches until a tap.
    expect(find.byKey(const ValueKey('category-icon-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('category-icon-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('category-bubble')), findsNothing);
    expect(find.text('25%'), findsNothing);
    expect(find.byTooltip('Следующие категории'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('category-icon-b')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('category-bubble')), findsOneWidget);
    expect(find.text('Дом'), findsOneWidget);
    expect(find.text(money(7500)), findsOneWidget);
    expect(find.text('75%'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('category-details')));
    expect(detail, 'b');
    // Tapping the ring itself picks the sector there.
    final painted = find
        .descendant(
          of: find.byType(CategoryOrbitChart),
          matching: find.byType(CustomPaint),
        )
        .first;
    final center = tester.getCenter(painted);
    final ring = tester.getSize(painted).height / 2 - 12 - 190 * .17 / 2;
    await tester.tapAt(center + Offset(ring * .7, -ring * .7));
    await tester.pumpAndSettle();
    expect(find.text('Еда'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('category-details')));
    expect(detail, 'a');
    // The middle lets go.
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('category-bubble')), findsNothing);
    expect(find.text('Ноябрь'), findsOneWidget);
  });
  testWidgets(
    'many categories stay on one ring with no lost totals or 320px overflows',
    (tester) async {
      final slices = List.generate(
        27,
        (i) => CategorySlice(
          id: '$i',
          name: 'Длинная категория $i',
          icon: Icons.shopping_bag_outlined,
          color: Colors.primaries[i % Colors.primaries.length],
          amount: 100,
        ),
      );
      await mount(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: CategoryOrbitChart(slices: slices, currency: 'RUB'),
            ),
          ),
        ),
        size: const Size(320, 800),
        scale: 1.5,
      );
      expect(find.text(money(2700)), findsOneWidget);
      expect(find.byTooltip('Следующие категории'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'ring keeps huge exact sums with accessibility text and rounds to 100 percent',
    (tester) async {
      final slices = List.generate(
        3,
        (i) => CategorySlice(
          id: '$i',
          name: 'Категория $i',
          icon: Icons.wallet_outlined,
          color: Colors.primaries[i],
          amount: 9007199254740991,
        ),
      );
      await mount(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: CategoryOrbitChart(slices: slices, currency: 'USD'),
            ),
          ),
        ),
        size: const Size(320, 800),
        scale: 1.8,
      );
      await tester.tap(find.byKey(const ValueKey('category-icon-0')));
      await tester.pumpAndSettle();
      expect(find.text('33,4%'), findsNWidgets(2));
      expect(find.text(money(9007199254740991, 'USD')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('category-icon-1')));
      await tester.pumpAndSettle();
      expect(find.text('33,3%'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('income ring and empty state keep correct income wording', (
    tester,
  ) async {
    await mount(
      tester,
      const Scaffold(
        body: CategoryOrbitChart(
          slices: [],
          currency: 'RUB',
          kind: EntryKind.income,
        ),
      ),
    );
    expect(find.text('Нет доходов за период'), findsOneWidget);
    expect(find.text('Нет расходов за период'), findsNothing);
    await mount(
      tester,
      const Scaffold(
        body: CategoryOrbitChart(
          slices: [
            CategorySlice(
              id: 'salary',
              name: 'Зарплата',
              icon: Icons.wallet_outlined,
              color: Colors.amber,
              amount: 100,
            ),
          ],
          currency: 'RUB',
          kind: EntryKind.income,
        ),
      ),
    );
    expect(find.text('Доходы'), findsOneWidget);
    expect(find.text('Расходы'), findsNothing);
  });
  testWidgets(
    'month details remain scrollable in landscape with large accessibility text',
    (tester) async {
      await mount(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: HalfYearChart(
              months: List.generate(
                6,
                (i) => MonthFlow(
                  month: DateTime(2026, 6 + i),
                  income: 9007199254740991,
                  expense: 0,
                ),
              ),
              currency: 'RUB',
            ),
          ),
        ),
        size: const Size(640, 320),
        scale: 1.8,
      );
      await tester.tap(find.byKey(const ValueKey('month-flow-5')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Разница'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'analytics six calendar months retain currency and exclude transfers and pending entries',
    (tester) async {
      final now = DateTime.now();
      final current = DateTime(now.year, now.month, 2);
      await tester.runAsync(
        () => controller.mutate(
          (d) => d.copyWith(
            accounts: [
              ...d.accounts,
              const Account(id: 'reserve', name: 'Резерв'),
              const Account(id: 'usd', name: 'USD', currency: 'USD'),
            ],
            preferences: d.preferences.copyWith(monthStart: 28),
            entries: [
              FinanceEntry(
                id: 'in',
                kind: EntryKind.income,
                amountMinor: 10000,
                currency: 'RUB',
                accountId: 'cash',
                categoryId: 'salary',
                date: current,
              ),
              FinanceEntry(
                id: 'out',
                kind: EntryKind.expense,
                amountMinor: 2500,
                currency: 'RUB',
                accountId: 'cash',
                categoryId: 'food',
                date: current,
              ),
              FinanceEntry(
                id: 'last-month',
                kind: EntryKind.income,
                amountMinor: 9000,
                currency: 'RUB',
                accountId: 'cash',
                categoryId: 'salary',
                date: DateTime(now.year, now.month, 0),
              ),
              FinanceEntry(
                id: 'transfer',
                kind: EntryKind.transfer,
                amountMinor: 7000,
                currency: 'RUB',
                accountId: 'cash',
                toAccountId: 'reserve',
                date: current,
              ),
              FinanceEntry(
                id: 'pending',
                kind: EntryKind.expense,
                amountMinor: 8000,
                currency: 'RUB',
                accountId: 'cash',
                categoryId: 'food',
                date: current,
                status: 'pending',
              ),
              FinanceEntry(
                id: 'foreign',
                kind: EntryKind.income,
                amountMinor: 40000,
                currency: 'USD',
                accountId: 'usd',
                categoryId: 'salary',
                date: current,
              ),
            ],
          ),
        ),
      );
      await mount(tester, const AnalyticsScreen());
      final chart = find.byType(HalfYearChart);
      await tester.scrollUntilVisible(
        chart,
        400,
        scrollable: find
            .descendant(
              of: find.byType(AnalyticsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final rendered = tester.widget<HalfYearChart>(chart);
      expect(rendered.months, hasLength(6));
      expect(rendered.months.first.month, DateTime(now.year, now.month - 5));
      expect(rendered.months.last.month, DateTime(now.year, now.month));
      expect(rendered.months.last.income, 10000);
      expect(rendered.months.last.expense, 2500);
      expect(rendered.months[4].income, 9000);
      expect(
        rendered.months.take(4).every((m) => m.income == 0 && m.expense == 0),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'six-month paired graph shows exact income and expenses on monthtap',
    (tester) async {
      final months = List.generate(
        6,
        (i) => MonthFlow(
          month: DateTime(2026, 6 + i),
          income: i == 0 ? 0 : 10000 * i,
          expense: 5000 * i,
        ),
      );
      await mount(
        tester,
        Scaffold(
          body: HalfYearChart(months: months, currency: 'RUB'),
        ),
        size: const Size(320, 740),
      );
      expect(find.text('Доходы'), findsOneWidget);
      expect(find.text('Расходы'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('month-flow-5')));
      await tester.pumpAndSettle();
      expect(find.text(money(50000)), findsOneWidget);
      expect(find.text(money(25000)), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
