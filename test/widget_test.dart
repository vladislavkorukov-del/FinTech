import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:finora/main.dart';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/entry_editor.dart';
import 'package:finora/presentation/screens/management.dart';
import 'package:finora/services/notification_service.dart';

class SilentNotifications extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
  @override
  Future<void> cancelAll() async {}
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late FinanceRepository repository;
  late FinanceController controller;
  setUp(() async {
    await initializeDateFormatting('ru');
    directory = await Directory.systemTemp.createTemp('finora-widget-');
    repository = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/ledger.db',
    );
    final seeded = await repository.load();
    // An install already in use (1.21 welcome screens done).
    controller = FinanceController(
      repository,
      SilentNotifications(),
      seeded.copyWith(
        preferences: seeded.preferences.copyWith(onboarded: true),
      ),
    );
  });
  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  for (final dark in [false, true]) {
    for (final size in [const Size(320, 640), const Size(740, 360)]) {
      testWidgets(
        'dashboard ${dark ? 'dark' : 'light'} ${size.width} has no overflow',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.runAsync(
            () => controller.preferences(
              controller.data.preferences.copyWith(
                theme: dark ? 'dark' : 'light',
              ),
            ),
          );
          await tester.pumpWidget(
            FinoraApp(controller: controller, requireDeviceSecurity: false),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('dashboard-actions')),
            findsOneWidget,
          );
          expect(find.text('Мои финансы'), findsNothing);
          expect(tester.takeException(), isNull);
          // Walk the entire dashboard; lazy rows/charts must lay out as well.
          final scroll = find.byType(Scrollable).first;
          for (var i = 0; i < 8; i++) {
            await tester.drag(scroll, const Offset(0, -300));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
  testWidgets('navigation, operation form and category editor render', (
    tester,
  ) async {
    await tester.pumpWidget(
      FinoraApp(controller: controller, requireDeviceSecurity: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Операции').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Фильтры'), findsOneWidget);
    await tester.tap(find.byTooltip('Добавить операцию'));
    await tester.pumpAndSettle();
    expect(find.byType(EntryEditor), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Сохранить операцию'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(EntryEditor),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Сохранить операцию'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ещё'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Категории'));
    await tester.pumpAndSettle();
    expect(find.byType(CategoriesScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'import is serialized with writes; restored data cannot be overwritten by an older mutation',
    () async {
      final exported = await repository.exportJson();
      final previous = controller.data.preferences;
      final a = controller.preferences(previous.copyWith(theme: 'light'));
      final b = controller.importJson(exported);
      final c = controller.mutate(
        (d) => d.copyWith(preferences: d.preferences.copyWith(accent: 'gold')),
      );
      await Future.wait([a, b, c]);
      final saved = await repository.load();
      expect(saved.preferences.theme, previous.theme);
      expect(saved.preferences.accent, 'gold');
      expect(controller.data.toJson(), saved.toJson());
    },
  );
}
