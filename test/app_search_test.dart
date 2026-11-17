import 'dart:io';

import 'package:finora/data/demo_data.dart';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/main.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/app_search.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

/// The side panel's search looks through the whole app: sections,
/// settings and the person's own data.
void main() {
  sqfliteFfiInit();

  test('matching ignores case and «ё»', () {
    expect(AppSearchScreen.matches('Пятёрочка', 'пятерочка'), isTrue);
    expect(AppSearchScreen.matches('Ozon', 'OZ'), isTrue);
    expect(AppSearchScreen.matches('Магнит', 'ozon'), isFalse);
  });

  testWidgets('finds a setting, a section and operations', (tester) async {
    await initializeDateFormatting('ru');
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('finora-search-'),
    );
    final repo = await tester.runAsync(
      () => FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir!.path}/s.db',
      ),
    );
    final demo = createDemoData(DateTime.now());
    await tester.runAsync(
      () => repo!.save(
        demo.copyWith(
          demo: false,
          preferences: demo.preferences.copyWith(
            onboarded: true,
            seenVersion: '1.0.0',
            releaseCelebrated: true,
          ),
        ),
      ),
    );
    final data = await tester.runAsync(repo!.load);
    final c = FinanceController(repo, _Quiet(), data!);
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinoraApp(controller: c, requireDeviceSecurity: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Функции'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('drawer-search')));
    await tester.pumpAndSettle();
    expect(find.byType(AppSearchScreen), findsOneWidget);
    // A setting by a word it answers to.
    await tester.enterText(
      find.byKey(const ValueKey('app-search-field')),
      'тёмная',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('search-hit-Внешний вид и темы')),
      findsOneWidget,
    );
    // The person's operations by the shop.
    final payee = c.data.entries.firstWhere((e) => e.payee.length > 3).payee;
    await tester.enterText(
      find.byKey(const ValueKey('app-search-field')),
      payee,
    );
    await tester.pump();
    expect(find.text('ОПЕРАЦИИ'), findsOneWidget);
    // A section switches the main screen's tab.
    await tester.enterText(
      find.byKey(const ValueKey('app-search-field')),
      'аналитика',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('search-hit-Аналитика')));
    await tester.pumpAndSettle();
    expect(find.byType(AppSearchScreen), findsNothing);
    expect(find.byKey(const ValueKey('nav-back')), findsOneWidget);
    // Back returns to the home tab.
    await tester.tap(find.byKey(const ValueKey('nav-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nav-back')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.runAsync(repo.close);
  });
}
