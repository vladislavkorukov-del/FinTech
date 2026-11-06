import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/main.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/widgets/service_badge.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

/// Finance 1.22.1: bank logos only where turned on; the main screen is
/// not squeezed by a keyboard that closes late.
void main() {
  sqfliteFfiInit();
  late Directory dir;
  late FinanceRepository repository;
  late FinanceController controller;
  setUp(() async {
    await initializeDateFormatting('ru');
    FlutterSecureStorage.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('finora-v1221-');
    repository = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/db',
    );
    await repository.save(
      FinanceData(
        accounts: [
          for (var i = 0; i < 8; i++)
            Account(
              id: 'a$i',
              name: 'Счёт $i',
              bank: i == 0 ? 'Сбербанк' : '',
              openingMinor: 1000 * i,
            ),
        ],
        members: const [Member(id: 'me', name: 'Я')],
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
    await dir.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinoraApp(controller: controller, requireDeviceSecurity: false),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no bank logo until it is turned on in the editor', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('Счёт 0'), findsOneWidget);
    expect(find.byKey(const ValueKey('service-badge-bank_1481')), findsNothing);
    // Turn it on for «Счёт 0».
    await tester.tap(find.byTooltip('Настроить счёт Счёт 0'));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('account-show-logo'));
    await tester.scrollUntilVisible(
      toggle,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить').last);
    for (
      var i = 0;
      i < 30 && controller.data.preferences.bankLogos.isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(controller.data.preferences.bankLogos, ['a0']);
    expect(find.byType(ServiceBadge), findsWidgets);
    expect(
      find.byKey(const ValueKey('service-badge-bank_1481')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late keyboard does not squeeze the main screen', (
    tester,
  ) async {
    await mount(tester);
    final full = tester.getSize(find.byType(Scrollable).first).height;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Scrollable).first).height, full);
    expect(tester.takeException(), isNull);
  });
}
