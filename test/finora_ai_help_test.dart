import 'dart:io';

import 'package:finora/data/demo_data.dart';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/features/finora_ai/ui/ai_help_screen.dart';
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

/// Settings → «Finora AI»: what she can do, and a question to try opens
/// the chat and is answered. (Its own file: the AI facade loads once per
/// test isolate.)
void main() {
  sqfliteFfiInit();

  testWidgets('Settings → Finora AI: a question to try opens the chat', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('finora-ai-help-'),
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
          theme: AppTheme.app(Brightness.light, 'tropic'),
          home: const AiHelpScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('КУДА УХОДЯТ ДЕНЬГИ'), findsOneWidget);
    await tester.tap(find.text('«Сравни этот месяц с прошлым»'));
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.byType(FinoraAiScreen), findsOneWidget);
    // The chat asked it on its own and answered.
    expect(find.textContaining('Сравни этот месяц с прошлым'), findsOneWidget);
    expect(find.byKey(const ValueKey('finora-ai-answer-0')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.runAsync(repo.close);
  });
}
