import 'dart:io';

import 'package:finora/data/demo_data.dart';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/main.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

/// Finora 1.27: payments reach the expenses only after «Оплачено».
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const voice = MethodChannel('finora/voice');
  late Directory dir;
  late FinanceRepository repository;
  late FinanceController controller;
  late List<String> heard;
  setUp(() async {
    await initializeDateFormatting('ru');
    FlutterSecureStorage.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('finora-v127-pay-');
    repository = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/db',
    );
    await repository.save(
      FinanceData(
        accounts: const [Account(id: 'card', name: 'Карта')],
        recurring: [
          RecurringRule(
            id: 'netflix',
            name: 'Netflix',
            accountId: 'card',
            categoryId: 'expense-9',
            amountMinor: 79900,
            automatic: true,
            paymentType: 'subscription',
            serviceId: 'netflix',
            nextDate: DateTime(
              DateTime.now().year,
              DateTime.now().month,
              DateTime.now().day,
              9,
            ),
          ),
        ],
        categories: createDemoData(DateTime(2026, 11, 6)).categories,
        members: const [Member(id: 'me', name: 'Я')],
        demo: false,
      ),
    );
    controller = FinanceController(
      repository,
      _Quiet(),
      await repository.load(),
    );
    heard = ['пятерочка 450 рублей', 'пятерочка 450'];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(voice, (
      call,
    ) async {
      if (call.method == 'listen') {
        return heard;
      }
      return true;
    });
  });
  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(voice, null);
    controller.dispose();
    await repository.close();
    await dir.delete(recursive: true);
  });

  Future<void> flush(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 60 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinoraApp(controller: controller, requireDeviceSecurity: false),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('an automatic subscription is not posted by itself', (
    tester,
  ) async {
    await tester.runAsync(controller.processRecurring);
    expect(controller.data.entries, isEmpty);
    expect(controller.duePayments().single.id, 'netflix');
  });

  testWidgets('Finora asks; «Оплачено» posts it and moves the date', (
    tester,
  ) async {
    await start(tester);
    expect(find.byKey(const ValueKey('payment-prompt')), findsOneWidget);
    expect(find.text('Сегодня списание подписки'), findsOneWidget);
    expect(find.text('Netflix'), findsWidgets);
    expect(controller.data.entries, isEmpty);
    await tester.tap(find.byKey(const ValueKey('payment-paid')));
    await flush(tester, () => controller.data.entries.isNotEmpty);
    await tester.pumpAndSettle();
    final entry = controller.data.entries.single;
    expect(entry.amountMinor, 79900);
    expect(entry.payee, 'Netflix');
    expect(entry.kind, EntryKind.expense);
    expect(
      controller.data.recurring.single.nextDate.isAfter(DateTime.now()),
      isTrue,
    );
    expect(find.byKey(const ValueKey('payment-prompt')), findsNothing);
    expect(find.byKey(const ValueKey('finora-says')), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('«Напомнить позже» and «В этот раз не платить»', (tester) async {
    await start(tester);
    await tester.tap(find.byKey(const ValueKey('payment-later')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('payment-prompt')), findsNothing);
    expect(controller.data.entries, isEmpty);
    expect(controller.duePayments(), isEmpty);
    expect(
      controller.duePayments(now: DateTime.now().add(const Duration(hours: 4))),
      hasLength(1),
    );
    await tester.pump(const Duration(seconds: 5));
  });
}
