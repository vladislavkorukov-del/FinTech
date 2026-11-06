import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:finora/main.dart';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/services/security_service.dart';
import 'package:finora/services/notification_service.dart';

class QuietNotifications extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

void main() {
  sqfliteFfiInit();
  testWidgets(
    'inactivity lock covers a pushed editor and retains it offstage',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      await initializeDateFormatting('ru');
      late Directory temp;
      late FinanceRepository repository;
      late FinanceController controller;
      await tester.runAsync(() async {
        temp = await Directory.systemTemp.createTemp('finora-gate-');
        repository = await FinanceRepository.open(
          factory: databaseFactoryFfi,
          path: '${temp.path}/db',
        );
        final data = await repository.load();
        controller = FinanceController(
          repository,
          QuietNotifications(),
          data.copyWith(
            preferences: data.preferences.copyWith(
              lockMinutes: 1,
              onboarded: true,
            ),
          ),
        );
      });
      await tester.pumpWidget(FinoraApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Операции').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Добавить операцию'));
      await tester.pumpAndSettle();
      expect(find.text('Новая операция'), findsOneWidget);
      // Simulate completing PIN enrollment while the app is already unlocked.
      // No invalid PIN is accepted here: the test only requires a stored record
      // to exercise the gate's presence and timer, never the verifier.
      FlutterSecureStorage.setMockInitialValues({
        'finora.pin.v1': 'configured-record',
      });
      SecurityService.revision.value++;
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(find.text('Введите PIN для входа в Finance'), findsOneWidget);
      expect(find.text('Новая операция'), findsNothing);
      expect(find.text('Новая операция', skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.runAsync(() async {
        await repository.close();
        await temp.delete(recursive: true);
      });
    },
  );
}
