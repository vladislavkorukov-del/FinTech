import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/payee_summary.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/dashboard.dart';
import 'package:finora/presentation/screens/entry_editor.dart';
import 'package:finora/presentation/screens/payee_summary_screen.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/presentation/widgets/common.dart';
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

/// Finance 1.8: tapping a recent operation opens a summary of everything spent
/// with that payee over a chosen period.
void main() {
  sqfliteFfiInit();
  final now = DateTime.now();
  DateTime daysAgo(int d, [int hour = 12]) =>
      DateTime(now.year, now.month, now.day - d, hour);
  FinanceEntry ride(
    String id,
    int minor,
    DateTime date, {
    String payee = 'Whoosh',
    String status = 'posted',
    String currency = 'RUB',
    EntryKind kind = EntryKind.expense,
  }) => FinanceEntry(
    id: id,
    kind: kind,
    amountMinor: minor,
    currency: currency,
    accountId: currency == 'RUB' ? 'card' : 'usd',
    categoryId: kind == EntryKind.expense ? 'fun' : 'salary',
    date: date,
    payee: payee,
    status: status,
  );
  final entries = [
    ride('a', 8290, daysAgo(0)),
    ride('b', 2697, daysAgo(0, 9)),
    ride('c', 15000, daysAgo(3), payee: 'WHOOSH '),
    ride('d', 5000, daysAgo(40)),
    ride('e', 99900, daysAgo(400)),
    ride('p', 7777, daysAgo(1), status: 'pending'),
    ride('x', 30000, daysAgo(1), payee: 'Самокат'),
    ride('u', 500, daysAgo(2), currency: 'USD'),
    ride('i', 100000, daysAgo(2), kind: EntryKind.income),
  ];

  group('domain', () {
    test('same payee and kind, posted only, per currency, period bounds', () {
      final s = PayeeSummary.compute(
        entries: entries,
        payee: 'whoosh.',
        kind: EntryKind.expense,
        start: daysAgo(6, 0),
        end: daysAgo(-1, 0),
      );
      expect(s.entries.map((e) => e.id), ['a', 'b', 'u', 'c']);
      expect(s.totals, {'RUB': 25987, 'USD': 500});
      expect(s.counts['RUB'], 3);
      expect(s.average('RUB'), 8662);
      final bars = s.buckets('RUB');
      expect(bars, hasLength(7));
      expect(bars.last.minor, 10987);
      expect(bars.fold<int>(0, (a, b) => a + b.minor), 25987);
    });
    test('long periods use calendar months; first date covers «all time»', () {
      final first = PayeeSummary.firstDate(
        entries,
        'Whoosh',
        EntryKind.expense,
      );
      expect(first, daysAgo(400));
      final s = PayeeSummary.compute(
        entries: entries,
        payee: 'Whoosh',
        kind: EntryKind.expense,
        start: first!,
        end: daysAgo(-1, 0),
      );
      expect(s.totals['RUB'], 130887);
      final bars = s.buckets('RUB');
      expect(bars.length, lessThanOrEqualTo(24));
      expect(bars.fold<int>(0, (a, b) => a + b.minor), 130887);
    });
    test('income keeps its own kind; empty payee matches nothing', () {
      expect(
        PayeeSummary.compute(
          entries: entries,
          payee: 'Whoosh',
          kind: EntryKind.income,
          start: DateTime(2000),
          end: DateTime(2100),
        ).totals,
        {'RUB': 100000},
      );
      expect(
        PayeeSummary.compute(
          entries: entries,
          payee: '  ',
          kind: EntryKind.expense,
          start: DateTime(2000),
          end: DateTime(2100),
        ).count,
        0,
      );
    });
  });

  group('screen', () {
    late Directory directory;
    late FinanceRepository repository;
    late FinanceController controller;
    setUp(() async {
      await initializeDateFormatting('ru');
      FlutterSecureStorage.setMockInitialValues({});
      directory = await Directory.systemTemp.createTemp('finance-payee-');
      repository = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/db',
      );
      await repository.save(
        FinanceData(
          accounts: const [
            Account(id: 'card', name: 'Карта', openingMinor: 1000000),
            Account(id: 'usd', name: 'USD', currency: 'USD'),
          ],
          categories: const [
            Category(id: 'fun', name: 'Развлечения', kind: EntryKind.expense),
            Category(id: 'salary', name: 'Зарплата', kind: EntryKind.income),
          ],
          members: const [Member(id: 'me', name: 'Я')],
          entries: entries,
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

    testWidgets('dashboard recent operation opens the payee summary', (
      tester,
    ) async {
      await mount(
        tester,
        Scaffold(
          body: Dashboard(onTransactions: () {}, onAnalytics: () {}),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Последние операции'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
      await tester.pumpAndSettle();
      final tile = find.text('Whoosh').first;
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.byType(PayeeSummaryScreen), findsOneWidget);
      expect(find.byType(EntryEditor), findsNothing);
      // Week: three RUB rides (82,90 + 26,97 + 150,00).
      await tester.tap(find.byKey(const ValueKey('payee-period-week')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('payee-total'))).data,
        money(25987),
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('payee-count'))).data,
        '4',
      );
      expect(find.text('+ ${money(500, 'USD')}'), findsOneWidget);
      // All time includes the ride from more than a year ago.
      await tester.ensureVisible(
        find.byKey(const ValueKey('payee-period-all')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('payee-period-all')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('payee-total'))).data,
        money(130887),
      );
      // The tapped operation is still editable from the summary.
      await tester.tap(find.byKey(const ValueKey('payee-edit-entry')));
      await tester.pumpAndSettle();
      expect(find.byType(EntryEditor), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final (size, scale) in [
      (const Size(320, 640), 1.5),
      (const Size(740, 360), 1.0),
    ]) {
      testWidgets('summary fits ${size.width}x${size.height} at text $scale', (
        tester,
      ) async {
        await mount(
          tester,
          PayeeSummaryScreen(entry: entries.first),
          size: size,
          scale: scale,
        );
        for (final p in PayeePeriod.values.where(
          (p) => p != PayeePeriod.custom,
        )) {
          await tester.ensureVisible(
            find.byKey(ValueKey('payee-period-${p.name}')),
          );
          await tester.tap(find.byKey(ValueKey('payee-period-${p.name}')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: p.name);
        }
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -800));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
