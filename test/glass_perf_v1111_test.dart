import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/main.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/management.dart';
import 'package:finora/presentation/widgets/motion.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

/// Finance 1.11.1: the glass must not cost frames. Once the entrance
/// animations end the app draws nothing until the user acts, the main
/// screen has only a handful of blurred panes, and long lists use clear
/// (unblurred) glass rows.
void main() {
  sqfliteFfiInit();
  late Directory temp;
  late FinanceRepository repository;
  late FinanceController controller;
  setUp(() async {
    await initializeDateFormatting('ru');
    temp = await Directory.systemTemp.createTemp('finora-v1111-perf-');
    repository = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${temp.path}/db',
    );
    final now = DateTime.now();
    await repository.save(
      FinanceData(
        accounts: const [Account(id: 'a', name: 'Карта', openingMinor: 100000)],
        categories: const [
          Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
        ],
        members: const [Member(id: 'me', name: 'Я')],
        entries: [
          for (var i = 0; i < 12; i++)
            FinanceEntry(
              id: 'e$i',
              kind: EntryKind.expense,
              amountMinor: 1000 + i,
              currency: 'RUB',
              accountId: 'a',
              categoryId: 'food',
              date: DateTime(now.year, now.month, now.day, 9, i),
              payee: 'Кафе $i',
            ),
        ],
        preferences: const AppPreferences(theme: 'dark'),
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

  testWidgets('idle main screen draws no frames; few blurred panes', (
    tester,
  ) async {
    Motion.debugForceAmbient = true;
    addTearDown(() => Motion.debugForceAmbient = false);
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinoraApp(controller: controller, requireDeviceSecurity: false),
    );
    await tester.pumpAndSettle();
    // Wait well past any one-shot effect, then nothing more is scheduled.
    await tester.pump(const Duration(seconds: 20));
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    final blurred = find.byType(BackdropFilter).evaluate().length;
    expect(blurred, inInclusiveRange(1, 8), reason: '$blurred blurred panes');
  });

  testWidgets('calendar day rows are clear glass, not blurred', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinoraApp(controller: controller, requireDeviceSecurity: false),
    );
    await tester.pumpAndSettle();
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute(builder: (_) => const CalendarScreen()));
    await tester.pumpAndSettle();
    final cafe = find.textContaining('Кафе');
    expect(cafe, findsWidgets);
    for (final row in cafe.evaluate()) {
      expect(
        find.ancestor(
          of: find.byWidget(row.widget),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
    }
  });
}
