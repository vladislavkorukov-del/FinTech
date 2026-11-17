import 'dart:io';

import 'package:finora/data/demo_data.dart';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/features/finora_ai/ui/finora_ai_screen.dart';
import 'package:finora/presentation/controller.dart';
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

/// Finora AI screen: the forecast and insights show, a quick question gets
/// an answer built from the engines' numbers.
void main() {
  sqfliteFfiInit();

  testWidgets('forecast, insights and a quick question', (tester) async {
    await initializeDateFormatting('ru');
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('finora-ai-ui-'),
    );
    final repo = await tester.runAsync(
      () => FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir!.path}/ai.db',
      ),
    );
    final demo = createDemoData(DateTime.now());
    await tester.runAsync(
      () => repo!.save(
        demo.copyWith(
          demo: false,
          preferences: demo.preferences.copyWith(onboarded: true),
        ),
      ),
    );
    final data = await tester.runAsync(repo!.load);
    final c = FinanceController(repo, _Quiet(), data!);
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinanceScope(
        controller: c,
        child: MaterialApp(
          theme: AppTheme.app(Brightness.dark, 'tropic'),
          home: const FinoraAiScreen(),
        ),
      ),
    );
    // The model loads from the asset bundle.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('finora-ai-headline')), findsOneWidget);
    expect(find.text('Чем займёмся\nсегодня?'), findsOneWidget);
    // A suggestion asks; the answer arrives after a short «thinking» beat.
    await tester.tap(find.text('Почему трачу больше?'));
    await tester.pump();
    expect(find.text('Финора считает…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('finora-ai-answer-0')), findsOneWidget);
    // A typed question in the chat.
    await tester.enterText(
      find.byKey(const ValueKey('finora-ai-question')),
      'Сколько останется после обязательных платежей?',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('finora-ai-send')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('finora-ai-answer-1')), findsOneWidget);
    expect(find.textContaining('После обязательных платежей'), findsWidgets);
    // The analysis sheet shows the forecast without words.
    await tester.tap(find.byKey(const ValueKey('finora-ai-analysis')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('finora-ai-forecast')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.runAsync(() async {
      await repo.close();
      await dir!.delete(recursive: true);
    });
  });
}
