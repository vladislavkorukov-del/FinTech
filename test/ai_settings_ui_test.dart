import 'dart:io';

import 'package:finora/data/demo_data.dart';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/features/finora_ai/ui/ai_settings_screen.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/entry_editor.dart';
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

/// The AI settings screen and the editor's place suggestions.
void main() {
  sqfliteFfiInit();
  late FinanceController c;
  late FinanceRepository repo;

  Future<void> start(WidgetTester tester, Widget home) async {
    await initializeDateFormatting('ru');
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('finora-ai-ui-'),
    );
    repo = (await tester.runAsync(
      () => FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir!.path}/a.db',
      ),
    ))!;
    final demo = createDemoData(DateTime.now());
    await tester.runAsync(
      () => repo.save(
        demo.copyWith(
          demo: false,
          entries: [
            ...demo.entries,
            for (var i = 0; i < 4; i++)
              FinanceEntry(
                id: 'kof$i',
                kind: EntryKind.expense,
                amountMinor: 35000,
                currency: 'RUB',
                accountId: demo.accounts.first.id,
                categoryId: demo.categories
                    .firstWhere((k) => k.kind == EntryKind.expense)
                    .id,
                payee: 'Кофемания',
                date: DateTime.now().subtract(Duration(days: i + 1)),
              ),
          ],
        ),
      ),
    );
    final data = await tester.runAsync(repo.load);
    c = FinanceController(repo, _Quiet(), data!);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinanceScope(
        controller: c,
        child: MaterialApp(
          theme: AppTheme.app(Brightness.light, 'tropic'),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Lets the database write finish.
  Future<void> settle(WidgetTester tester, bool Function() saved) async {
    for (var i = 0; i < 150 && !saved(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
    }
  }

  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.runAsync(repo.close);
  }

  testWidgets('switches and the automation level are saved', (tester) async {
    await start(tester, const AiSettingsScreen());
    expect(c.data.preferences.ai.personalization, isTrue);
    await tester.ensureVisible(
      find.byKey(const ValueKey('ai-setting-personalization')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ai-setting-personalization')),
        matching: find.byType(Switch),
      ),
    );
    await settle(tester, () => !c.data.preferences.ai.personalization);
    expect(c.data.preferences.ai.personalization, isFalse);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('ai-level-suggestOnly')),
      -200,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-level-suggestOnly')));
    await settle(
      tester,
      () => c.data.preferences.ai.automation == AiAutomation.suggestOnly,
    );
    expect(c.data.preferences.ai.automation, AiAutomation.suggestOnly);
    // Reset asks first.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('ai-reset')),
      200,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('ai-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-reset')));
    await tester.pumpAndSettle();
    expect(find.text('Сбросить персонализацию?'), findsOneWidget);
    await stop(tester);
  });

  testWidgets('a place seen before is offered and fills the form', (
    tester,
  ) async {
    await start(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showEntryEditor(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final payee = find.byKey(const ValueKey('entry-payee'));
    await tester.scrollUntilVisible(
      payee,
      300,
      scrollable: find
          .descendant(
            of: find.byType(EntryEditor),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.enterText(payee, 'Кофе');
    await tester.pump();
    final chip = find.ancestor(
      of: find.textContaining('Кофемания'),
      matching: find.byType(ActionChip),
    );
    expect(chip, findsOneWidget);
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
    final field = tester.widget<EditableText>(
      find.descendant(of: payee, matching: find.byType(EditableText)),
    );
    expect(field.controller.text, 'Кофемания');
    await stop(tester);
  });
}
