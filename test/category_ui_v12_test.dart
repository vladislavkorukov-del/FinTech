import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/finance_engine.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/management.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _QuietNotifications extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late FinanceRepository repository;
  late FinanceController controller;
  final today = DateTime(2026, 11, 5);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('finora-category-v12-');
    repository = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/ledger.db',
    );
    await repository.save(
      FinanceData(
        accounts: const [
          Account(id: 'cash', name: 'Наличные', openingMinor: 100000),
        ],
        categories: const [
          Category(
            id: 'food',
            name: 'Продукты',
            kind: EntryKind.expense,
            color: 0xFFD67C7E,
            background: 0xFF403021,
          ),
          Category(
            id: 'other',
            name: 'Хобби',
            kind: EntryKind.expense,
            order: 1,
          ),
          Category(id: 'salary', name: 'Зарплата', kind: EntryKind.income),
        ],
        entries: [
          FinanceEntry(
            id: 'purchase',
            kind: EntryKind.expense,
            amountMinor: 4500,
            currency: 'RUB',
            accountId: 'cash',
            categoryId: 'food',
            date: today,
          ),
        ],
        members: const [Member(id: 'me', name: 'Я')],
        preferences: const AppPreferences(theme: 'dark', accent: 'coffee'),
      ),
    );
    controller = FinanceController(
      repository,
      _QuietNotifications(),
      await repository.load(),
    );
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
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
          home: const CategoriesScreen(),
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
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!ready()) {
        if (DateTime.now().isAfter(deadline)) {
          throw TestFailure('Category action was not persisted');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> reopen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.runAsync(() async {
      await repository.close();
      repository = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/ledger.db',
      );
      controller = FinanceController(
        repository,
        _QuietNotifications(),
        await repository.load(),
      );
    });
    await mount(tester);
  }

  testWidgets(
    'creates explicit income category, saves custom color and reopens it',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byTooltip('Добавить категорию'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('category-kind')), findsOneWidget);
      await tester.tap(find.text('Доход'));
      await tester.enterText(find.byType(TextFormField).first, 'Продажа вещей');
      final swatch = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Цвет ff8ea9a4',
      );
      await tester.ensureVisible(swatch);
      await tester.tap(swatch);
      await commit(
        tester,
        find.text('Сохранить'),
        () => controller.data.categories.any((c) => c.name == 'Продажа вещей'),
      );
      final saved = controller.data.categories.firstWhere(
        (c) => c.name == 'Продажа вещей',
      );
      expect(saved.kind, EntryKind.income);
      expect(saved.color, 0xFF8EA9A4);
      expect(saved.archived, isFalse);
      await reopen(tester);
      expect(controller.category(saved.id)!.color, 0xFF8EA9A4);
      await tester.tap(find.text('Доходы'));
      await tester.pumpAndSettle();
      expect(find.text('Продажа вещей'), findsOneWidget);
      await tester.tap(find.text('Продажа вещей'));
      await tester.pumpAndSettle();
      expect(find.text('Тип: Доход'), findsOneWidget);
      expect(find.byKey(const ValueKey('category-kind')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'renames, archives and restores used category without changing history',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('Продукты'));
      await tester.pumpAndSettle();
      expect(find.text('Тип: Расход'), findsOneWidget);
      expect(find.byKey(const ValueKey('category-kind')), findsNothing);
      await tester.enterText(find.byType(TextFormField).first, 'Питание');
      await commit(
        tester,
        find.text('Сохранить'),
        () => controller.category('food')!.name == 'Питание',
      );
      await tester.tap(find.text('Питание'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Переместить в архив'));
      await tester.tap(find.text('Переместить в архив'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Все операции, бюджеты и аналитика сохранятся.'),
        findsOneWidget,
      );
      await commit(
        tester,
        find.text('Продолжить'),
        () => controller.category('food')!.archived,
      );
      expect(find.text('Питание'), findsNothing);
      expect(controller.data.entries.single.categoryId, 'food');
      expect(
        FinanceEngine.totals(
          controller.data.entries,
          DateTime(2026, 11),
          DateTime(2026, 12),
          'RUB',
        ).expense,
        4500,
      );
      await reopen(tester);
      expect(controller.category('food')!.archived, isTrue);
      await tester.tap(find.text('Архив (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Питание'), findsOneWidget);
      await commit(
        tester,
        find.byTooltip('Восстановить категорию'),
        () => !controller.category('food')!.archived,
      );
      await tester.tap(find.text('Архив (0)'));
      await tester.pumpAndSettle();
      expect(find.text('Питание'), findsOneWidget);
      expect(controller.category('food')!.color, 0xFFD67C7E);
      expect(controller.data.entries.single.amountMinor, 4500);
    },
  );

  testWidgets('deletes unused category and deletion survives reopening', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Хобби'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Удалить категорию'));
    await tester.tap(find.text('Удалить категорию'));
    await tester.pumpAndSettle();
    expect(find.textContaining('нет связанных операций'), findsOneWidget);
    await commit(
      tester,
      find.text('Продолжить'),
      () => controller.category('other') == null,
    );
    await reopen(tester);
    expect(controller.category('other'), isNull);
    expect(find.text('Хобби'), findsNothing);
    expect(controller.data.entries.single.categoryId, 'food');
  });
}
