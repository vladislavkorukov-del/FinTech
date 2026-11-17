import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/main.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

/// Finance 1.9.1: the bottom menu reaches the bottom edge of the phone. Under
/// edge-to-edge Android the system navigation area is painted with the bar's
/// color instead of leaving a strip of backdrop under it.
void main() {
  sqfliteFfiInit();
  late Directory temp;
  late FinanceRepository repository;
  late FinanceController controller;
  setUp(() async {
    await initializeDateFormatting('ru');
    temp = await Directory.systemTemp.createTemp('finora-v191-nav-');
    repository = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${temp.path}/db',
    );
    await repository.save(
      const FinanceData(
        accounts: [Account(id: 'a', name: 'Карта', openingMinor: 100000)],
        categories: [],
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

  for (final inset in [0.0, 24.0, 48.0]) {
    testWidgets('the side panel opens above the system bar (inset $inset)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 860);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = FakeViewPadding(top: 24, bottom: inset);
      tester.view.viewPadding = FakeViewPadding(top: 24, bottom: inset);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        FinoraApp(controller: controller, requireDeviceSecurity: false),
      );
      await tester.pumpAndSettle();
      // Release: no bottom bar and, for now, no voice orb on the screen.
      expect(find.byKey(const ValueKey('bottom-nav')), findsNothing);
      expect(find.byKey(const ValueKey('bottom-orb')), findsNothing);
      // The menu button opens the side panel with every place.
      await tester.tap(find.byKey(const ValueKey('nav-menu')));
      await tester.pumpAndSettle();
      for (final label in [
        'Главная',
        'Операции',
        'Аналитика',
        'Finora AI',
        'Ещё',
      ]) {
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('app-drawer')),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }
      expect(find.byKey(const ValueKey('drawer-new-entry')), findsOneWidget);
      // The new-operation button stays above the system navigation area.
      final button = tester.getRect(
        find.byKey(const ValueKey('drawer-new-entry')),
      );
      expect(button.bottom, lessThanOrEqualTo(860 - inset));
    });
  }

  testWidgets('a swipe right from the left fifth opens the panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinoraApp(controller: controller, requireDeviceSecurity: false),
    );
    await tester.pumpAndSettle();
    final drawer = find.byKey(const ValueKey('app-drawer'));
    // From the middle of the screen: nothing opens.
    await tester.dragFrom(const Offset(200, 500), const Offset(260, 0));
    await tester.pumpAndSettle();
    expect(drawer, findsNothing);
    // From the left fifth (x < 80): the panel opens.
    await tester.dragFrom(const Offset(40, 500), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(drawer, findsOneWidget);
  });

  testWidgets('the edge swipe opens the panel from an inner page too', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinoraApp(controller: controller, requireDeviceSecurity: false),
    );
    await tester.pumpAndSettle();
    // An inner page from «Полезное»: the shopping list.
    await tester.tap(find.byKey(const ValueKey('nav-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drawer-shopping')));
    await tester.pumpAndSettle();
    final drawer = find.byKey(const ValueKey('app-drawer'));
    expect(drawer, findsNothing);
    // From the middle: the page stays.
    await tester.dragFrom(const Offset(200, 500), const Offset(260, 0));
    await tester.pumpAndSettle();
    expect(drawer, findsNothing);
    // From the left fifth: the page closes and the panel opens.
    await tester.dragFrom(const Offset(30, 500), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(drawer, findsOneWidget);
  });
}
