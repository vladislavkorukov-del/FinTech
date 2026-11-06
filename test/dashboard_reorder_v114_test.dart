import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/main.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

/// Finance 1.14: main-screen blocks, accounts and goals are dragged into a
/// new order with a long press, and the order is kept.
void main() {
  sqfliteFfiInit();
  late Directory temp;
  late FinanceRepository repository;
  late FinanceController controller;
  setUp(() async {
    await initializeDateFormatting('ru');
    temp = await Directory.systemTemp.createTemp('finora-v114-reorder-');
    repository = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${temp.path}/db',
    );
    await repository.save(
      const FinanceData(
        accounts: [
          Account(id: 'a', name: 'Счёт А', openingMinor: 100000),
          Account(id: 'b', name: 'Счёт Б', openingMinor: 200000),
          Account(id: 'c', name: 'Счёт В', openingMinor: 300000),
        ],
        goals: [
          Goal(id: 'g1', name: 'Отпуск', targetMinor: 100000),
          Goal(id: 'g2', name: 'Ноутбук', targetMinor: 200000),
        ],
        members: [Member(id: 'me', name: 'Я')],
        preferences: AppPreferences(theme: 'dark'),
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
    await temp.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinoraApp(controller: controller, requireDeviceSecurity: false),
    );
    await tester.pumpAndSettle();
  }

  Future<void> drag(WidgetTester tester, Finder from, Finder to) async {
    final start = tester.getCenter(from);
    final end = tester.getTopLeft(to) - const Offset(0, 8);
    final gesture = await tester.startGesture(start);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(
        Offset.lerp(start, Offset(start.dx, end.dy), i / 10)!,
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    // The new order shows at once; the database write finishes in real time.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  double top(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  testWidgets('a block is dragged above another and stays there', (
    tester,
  ) async {
    await mount(tester);
    expect(
      top(tester, 'Все счета'),
      lessThan(top(tester, 'Мечты и накопления')),
    );
    await drag(tester, find.text('Мечты и накопления'), find.text('Все счета'));
    expect(
      top(tester, 'Мечты и накопления'),
      lessThan(top(tester, 'Все счета')),
    );
    final order = controller.data.preferences.dashboardOrder;
    expect(order.indexOf('goals'), lessThan(order.indexOf('accounts')));
    // Saved: a fresh load has the same order.
    final saved = (await tester.runAsync(repository.load))!;
    expect(saved.preferences.dashboardOrder, order);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accounts and goals reorder inside their blocks', (tester) async {
    await mount(tester);
    await drag(tester, find.text('Счёт В'), find.text('Счёт А'));
    expect(top(tester, 'Счёт В'), lessThan(top(tester, 'Счёт А')));
    expect(controller.data.preferences.accountOrder, ['c', 'a', 'b']);
    // The blocks themselves did not move.
    expect(controller.data.preferences.dashboardOrder, isEmpty);
    await drag(tester, find.text('Ноутбук'), find.text('Отпуск'));
    expect(controller.data.preferences.goalOrder, ['g2', 'g1']);
    final saved = (await tester.runAsync(repository.load))!;
    expect(saved.preferences.accountOrder, ['c', 'a', 'b']);
    expect(saved.preferences.goalOrder, ['g2', 'g1']);
    // A short tap still opens things as before (no drag on a tap).
    await tester.tap(find.text('Все счета'));
    await tester.pumpAndSettle();
    expect(controller.data.preferences.dashboardOrder, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('saved order ignores unknown ids and appends new ones', () {
    final arranged = AppPreferences.arrange(
      ['summary', 'quick', 'accounts', 'recent'],
      ['recent', 'gone', 'summary'],
      (id) => id,
    );
    expect(arranged, ['recent', 'summary', 'quick', 'accounts']);
    final json = const AppPreferences(
      dashboardOrder: ['recent'],
      accountOrder: ['b'],
      goalOrder: ['g'],
    ).toJson();
    final back = AppPreferences.fromJson(json);
    expect(back.dashboardOrder, ['recent']);
    expect(back.accountOrder, ['b']);
    expect(back.goalOrder, ['g']);
    // Settings saved by earlier versions have no order: the default one.
    expect(AppPreferences.fromJson({}).dashboardOrder, isEmpty);
  });
}
