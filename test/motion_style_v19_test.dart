import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/dashboard.dart';
import 'package:finora/presentation/screens/settings.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/presentation/widgets/common.dart';
import 'package:finora/presentation/widgets/motion.dart';
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

/// Finance 1.9: centered income/expense tiles, motion that always settles in
/// place (and is skipped with «reduce motion»), and the style gallery.
void main() {
  sqfliteFfiInit();
  late Directory directory;
  late FinanceRepository repository;
  late FinanceController controller;
  setUp(() async {
    await initializeDateFormatting('ru');
    FlutterSecureStorage.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('finance-motion-');
    repository = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/db',
    );
    final now = DateTime.now();
    await repository.save(
      FinanceData(
        accounts: const [
          Account(id: 'card', name: 'Карта', openingMinor: 500000),
        ],
        categories: const [
          Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
          Category(id: 'salary', name: 'Зарплата', kind: EntryKind.income),
        ],
        members: const [Member(id: 'me', name: 'Я')],
        entries: [
          FinanceEntry(
            id: 'in',
            kind: EntryKind.income,
            amountMinor: 9000000,
            currency: 'RUB',
            accountId: 'card',
            categoryId: 'salary',
            date: now,
            payee: 'Работа',
          ),
          FinanceEntry(
            id: 'out',
            kind: EntryKind.expense,
            amountMinor: 1971338,
            currency: 'RUB',
            accountId: 'card',
            categoryId: 'food',
            date: now,
            payee: 'Магнит',
          ),
        ],
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
    await directory.delete(recursive: true);
  });
  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    bool reduce = false,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FinanceScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.app(Brightness.dark, 'sunset'),
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
            child: child!,
          ),
          home: page,
        ),
      ),
    );
  }

  testWidgets('income and expense tiles are centered and settle exactly', (
    tester,
  ) async {
    await mount(
      tester,
      Scaffold(
        body: Dashboard(onTransactions: () {}, onAnalytics: () {}),
      ),
    );
    // Mid-animation the amount is still counting up.
    Finder inTiles(String text) => find.descendant(
      of: find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('summary-'),
      ),
      matching: find.text(text),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(inTiles(money(1971338)), findsNothing);
    await tester.pumpAndSettle();
    for (final (label, amount) in [('Доходы', 9000000), ('Расходы', 1971338)]) {
      final value = inTiles(money(amount));
      expect(value, findsOneWidget);
      final tile = find
          .ancestor(of: find.text(label), matching: find.byType(GlassSurface))
          .first;
      final center = tester.getCenter(tile).dx;
      expect(tester.getCenter(value).dx, closeTo(center, 1.5), reason: label);
      final row = find
          .ancestor(of: find.text(label), matching: find.byType(Row))
          .first;
      expect(tester.getCenter(row).dx, closeTo(center, 1.5), reason: label);
    }
    // Every section has finished its entrance: fully opaque, in place.
    for (final reveal in tester.widgetList<Opacity>(
      find.descendant(of: find.byType(Reveal), matching: find.byType(Opacity)),
    )) {
      expect(reveal.opacity, 1);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('income and expense tiles are compact', (tester) async {
    await mount(
      tester,
      Scaffold(
        body: Dashboard(onTransactions: () {}, onAnalytics: () {}),
      ),
      reduce: true,
    );
    await tester.pump();
    final heights = <double>[];
    for (final title in ['Доходы', 'Расходы']) {
      final tile = tester.getSize(find.byKey(ValueKey('summary-$title')));
      heights.add(tile.height);
      // 1.17: was about 74 px high.
      // ignore: avoid_print
      print('$title tile ${tile.height}');
      expect(tile.height, lessThanOrEqualTo(56), reason: title);
    }
    expect(heights.first, heights.last, reason: 'both tiles are equal');
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce motion shows final values on the first frame', (
    tester,
  ) async {
    await mount(
      tester,
      Scaffold(
        body: Dashboard(onTransactions: () {}, onAnalytics: () {}),
      ),
      reduce: true,
    );
    await tester.pump();
    Finder inTiles(String text) => find.descendant(
      of: find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('summary-'),
      ),
      matching: find.text(text),
    );
    expect(inTiles(money(1971338)), findsOneWidget);
    expect(inTiles(money(9000000)), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('style gallery selects and persists a reference theme', (
    tester,
  ) async {
    await mount(tester, const SettingsScreen(section: 'appearance'));
    // Settings shows a progress indicator while it reads device security.
    await tester.pump(const Duration(milliseconds: 500));
    final gallery = find.byKey(const ValueKey('style-gallery'));
    await tester.ensureVisible(gallery);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('style-emerald')),
      200,
      scrollable: find.descendant(
        of: gallery,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('style-emerald')));
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (controller.data.preferences.accent != 'emerald') {
        if (DateTime.now().isAfter(deadline)) fail('style not saved');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump(const Duration(milliseconds: 500));
    final saved = await tester.runAsync(() => repository.load());
    expect(saved!.preferences.accent, 'emerald');
    expect(tester.takeException(), isNull);
  });
}
