import 'dart:io';

import 'package:finora/data/demo_data.dart';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/debts_screen.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

/// «Долги»: a debt added from the screen gets Finora's payoff plan.
void main() {
  testWidgets('adding a loan shows it with a payoff plan', (tester) async {
    sqfliteFfiInit();
    await initializeDateFormatting('ru');
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('finora-debts-'),
    );
    final repo = (await tester.runAsync(
      () => FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir!.path}/a.db',
      ),
    ))!;
    final demo = createDemoData(DateTime.now());
    await tester.runAsync(
      () => repo.save(demo.copyWith(demo: false, recurring: const [])),
    );
    final c = FinanceController(
      repo,
      _Quiet(),
      (await tester.runAsync(repo.load))!,
    );
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinanceScope(
        controller: c,
        child: MaterialApp(
          theme: AppTheme.app(Brightness.light, 'tropic'),
          home: const DebtsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Долгов нет'), findsOneWidget);
    // The help explains with examples.
    await tester.tap(find.byKey(const ValueKey('debts-help-empty')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('debts-help')), findsOneWidget);
    expect(find.textContaining('Например: Сбербанк'), findsOneWidget);
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('debts-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('debt-name')), 'Кредитка');
    await tester.enterText(find.byKey(const ValueKey('debt-total')), '60000');
    await tester.enterText(find.byKey(const ValueKey('debt-rate')), '30');
    await tester.enterText(find.byKey(const ValueKey('debt-payment')), '3000');
    await tester.ensureVisible(find.byKey(const ValueKey('debt-save')));
    await tester.tap(find.byKey(const ValueKey('debt-save')));
    for (var i = 0; i < 100 && c.data.recurring.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final rule = c.data.recurring.single;
    expect(rule.isLoan, isTrue);
    expect(rule.principalMinor, 6000000);
    expect(rule.interestRate, 30);
    expect(rule.amountMinor, 300000);
    expect(find.byKey(ValueKey('debt-${rule.id}')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('debts-plan')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Без долгов к'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.runAsync(repo.close);
  });
}
