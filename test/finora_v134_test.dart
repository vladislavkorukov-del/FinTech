import 'dart:io';

import 'package:finora/data/demo_data.dart';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/data/finora_csv.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/main.dart';
import 'package:finora/presentation/haptics.dart';
import 'package:finora/presentation/widgets/common.dart';
import 'package:finora/presentation/widgets/finora_orb.dart';
import 'package:finora/presentation/widgets/service_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Finora 1.34: the whole base in CSV, standard icons for payments, the
/// loading screen text under Finora, firmer haptics.
void main() {
  sqfliteFfiInit();
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('finora-v134-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Future<FinanceRepository> open(String name) => FinanceRepository.open(
    factory: databaseFactoryFfi,
    path: '${temp.path}/$name.db',
  );

  FinanceData sample() {
    final demo = createDemoData(DateTime(2026, 11, 7));
    return demo.copyWith(
      recurring: [
        for (final r in demo.recurring) r,
        RecurringRule(
          id: 'rent',
          name: '=Аренда, "квартира"\nэтаж 2',
          accountId: demo.accounts.first.id,
          categoryId: demo.categories
              .firstWhere((c) => c.kind == EntryKind.expense)
              .id,
          amountMinor: 3500000,
          nextDate: DateTime(2026, 11, 25),
          icon: 12,
          color: 0xFFD67C7E,
        ),
      ],
      preferences: demo.preferences.copyWith(
        userName: '-Влад',
        language: 'en',
        haptics: false,
      ),
      demo: false,
    );
  }

  group('whole base CSV', () {
    test('export → import gives back the same base', () async {
      final a = await open('a');
      await a.save(sample());
      final csv = await a.exportFullCsv();
      expect(csv, startsWith('﻿"Finora CSV"'));
      for (final section in [
        '#accounts',
        '#categories',
        '#entries',
        '#budgets',
        '#goals',
        '#recurring',
        '#members',
        '#preferences',
        '#meta',
      ]) {
        expect(csv, contains('"$section"'));
      }
      // Formulas are not run by spreadsheets.
      expect(csv, contains('"\'=Аренда, ""квартира""'));

      final b = await open('b');
      await b.importCsv(csv);
      final before = (await a.load()).toJson();
      final after = (await b.load()).toJson();
      expect(after, before);
      final rent = (await b.load()).recurring.firstWhere((r) => r.id == 'rent');
      expect(rent.name, '=Аренда, "квартира"\nэтаж 2');
      expect(rent.icon, 12);
      expect(rent.color, 0xFFD67C7E);
      expect((await b.load()).preferences.userName, '-Влад');
      await a.close();
      await b.close();
    });

    test('a table re-saved by Russian Excel (semicolons) still opens', () {
      const semi =
          '\uFEFFFinora CSV;1\r\n#accounts\r\nid:text;openingMinor:int;'
          'note:text\r\na1;150000;"Зарплатная; карта"\r\n\r\n'
          '#categories\r\n#entries\r\n#budgets\r\n#goals\r\n'
          '#recurring\r\n#members\r\n#preferences\r\nkey:text;value:text\r\n'
          'theme;"""dark"""\r\n';
      final back = FinoraCsv.decode(semi, schema: 4)['data']! as Map;
      expect((back['accounts'] as List).single, {
        'id': 'a1',
        'openingMinor': 150000,
        'note': 'Зарплатная; карта',
      });
      expect(back['preferences'], {'theme': 'dark'});
    });

    test('a foreign or damaged table changes nothing', () async {
      final repo = await open('c');
      await repo.save(sample());
      final before = (await repo.load()).toJson();
      for (final bad in [
        'id,amount\n1,2\n',
        '"Finora CSV","1"\n"#accounts"\n',
        '"Finora CSV","1"\n"#accounts"\n"id:text","openingMinor:int"\n"a","много"\n',
        '"Finora CSV","1"\n"#accounts"\n"id:text\n',
      ]) {
        await expectLater(repo.importCsv(bad), throwsFormatException);
      }
      expect((await repo.load()).toJson(), before);
      await repo.close();
    });

    test('empty text and nothing stay different', () {
      final data = {
        'accounts': [
          {'id': 'x', 'note': '', 'bank': null, 'n': 5, 'ok': true},
        ],
        'categories': [],
        'entries': [],
        'budgets': [],
        'goals': [],
        'recurring': [],
        'members': [],
        'preferences': {
          'theme': 'dark',
          'dashboardOrder': ['a', 'b'],
        },
        'demo': true,
      };
      final back =
          FinoraCsv.decode(FinoraCsv.encode(data), schema: 4)['data']! as Map;
      expect((back['accounts'] as List).single, {
        'id': 'x',
        'note': '',
        'bank': null,
        'n': 5,
        'ok': true,
      });
      expect(back['preferences'], data['preferences']);
      expect(back['demo'], true);
    });
  });

  group('standard icons for payments', () {
    test('kept in the base, and an old base gets the new columns', () async {
      final repo = await open('old');
      await repo.save(sample());
      await repo.close();
      // Make it a 1.33 base: no icon columns, schema 3.
      final raw = await databaseFactoryFfi.openDatabase('${temp.path}/old.db');
      await raw.execute('ALTER TABLE recurring DROP COLUMN icon');
      await raw.execute('ALTER TABLE recurring DROP COLUMN color');
      await raw.execute('ALTER TABLE recurring DROP COLUMN totalMinor');
      await raw.setVersion(3);
      await raw.close();

      final again = await open('old');
      final data = await again.load();
      expect(data.recurring.firstWhere((r) => r.id == 'rent').icon, isNull);
      await again.save(
        data.copyWith(
          recurring: [
            for (final r in data.recurring)
              r.id == 'rent' ? r.copyWith(icon: 7, color: 0xFF000001) : r,
          ],
        ),
      );
      final rent = (await again.load()).recurring.firstWhere(
        (r) => r.id == 'rent',
      );
      expect(rent.icon, 7);
      expect(rent.color, 0xFF000001);
      expect(rent.copyWith(icon: null).icon, isNull);
      await again.close();
    });

    testWidgets('the badge shows the chosen icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ServiceBadge(name: 'Netflix', icon: 3, iconColor: 0xFFD67C7E),
          ),
        ),
      );
      expect(find.byType(CategoryBadge), findsOneWidget);
      expect(find.byIcon(categoryIcon(3)), findsOneWidget);
    });
  });

  testWidgets('loading screen: the words are below Finora', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(padding: EdgeInsets.all(28), child: HelloFinora()),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final orb = tester.getRect(find.byType(FinoraCharacter));
    final words = tester.getRect(
      find.byKey(const ValueKey('loading-finora-text')),
    );
    final screen = tester.getRect(find.byType(Scaffold));
    expect(orb.center.dy, closeTo(screen.center.dy, 1));
    expect(words.top, greaterThan(orb.bottom + 20));
    expect(find.text('Привет! Я Финора'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('haptics: a firm pulse from the motor', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('finora/system'),
      (call) async {
        calls.add(call);
        return true;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('finora/system'),
        null,
      ),
    );
    Haptics.enabled = true;
    Haptics.tap();
    await Haptics.success();
    Haptics.heavy();
    await tester.pump();
    expect(calls.map((c) => c.method), everyElement('vibrate'));
    final strengths = [
      for (final c in calls) (c.arguments as Map)['amplitude'] as int,
    ];
    expect(strengths.length, 3);
    expect(strengths.every((a) => a >= 170), isTrue);
    Haptics.enabled = false;
    Haptics.tap();
    await tester.pump();
    expect(calls.length, 3);
    Haptics.enabled = true;
  });
}
