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
    testWidgets('bottom menu touches the screen bottom (inset $inset)', (
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
      final bar = find.byKey(const ValueKey('bottom-nav'));
      final rect = tester.getRect(bar);
      expect(rect.bottom, 860, reason: 'no gap under the menu');
      final box = tester.widget<DecoratedBox>(bar);
      final color = (box.decoration as BoxDecoration).color!;
      expect(color.a, 1, reason: 'opaque, backdrop does not show through');
      // The buttons stay above the system navigation area.
      final label = tester.getRect(find.text('Главная'));
      expect(label.bottom, lessThanOrEqualTo(860 - inset));
    });
  }
}
