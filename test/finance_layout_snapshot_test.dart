import 'dart:io';
import 'dart:ui' as ui;

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/main.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/screenshot_fonts.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

/// Also run against the pre-world revision to compare the four existing tabs.
/// Set FINORA_CAPTURE_DIR to capture actual Flutter-rendered pixels.
void main() {
  testWidgets('main tabs keep their order, labels and financial layout', (
    tester,
  ) async {
    sqfliteFfiInit();
    if (Platform.environment.containsKey('FINORA_CAPTURE_DIR')) {
      await tester.runAsync(loadScreenshotFonts);
    }
    await initializeDateFormatting('ru');
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('finora-layout-'),
    );
    final repo = await tester.runAsync(
      () => FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir!.path}/ledger.db',
      ),
    );
    await tester.runAsync(
      () => repo!.save(
        FinanceData(
          accounts: const [
            Account(id: 'a', name: 'Основная карта', openingMinor: 1234567),
          ],
          categories: const [
            Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
          ],
          members: const [Member(id: 'me', name: 'Я')],
          entries: [
            FinanceEntry(
              id: 'e',
              kind: EntryKind.expense,
              amountMinor: 25900,
              currency: 'RUB',
              accountId: 'a',
              categoryId: 'food',
              date: DateTime(2026, 11, 8, 10),
              memberId: 'me',
              payee: 'Магазин',
            ),
          ],
        ),
      ),
    );
    final data = await tester.runAsync(repo!.load);
    final c = FinanceController(repo, _Quiet(), data!);
    addTearDown(() async {
      c.dispose();
      await repo.close();
      await dir!.delete(recursive: true);
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinanceScope(
        controller: c,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark, 'coffee'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const RepaintBoundary(
            key: ValueKey('finance-capture'),
            child: HomeShell(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    final nav = find.byKey(const ValueKey('bottom-nav'));
    expect(nav, findsOneWidget);
    final navText = tester
        .widgetList<Text>(
          find.descendant(
            of: nav,
            matching: find.byWidgetPredicate((w) => w is Text),
          ),
        )
        .map((w) => w.data)
        .whereType<String>()
        .toList();
    expect(navText, ['Главная', 'Операции', 'Аналитика', 'Ещё']);
    for (final tab in ['Главная', 'Операции', 'Аналитика', 'Ещё']) {
      await tester.tap(find.descendant(of: nav, matching: find.text(tab)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
      final output = Platform.environment['FINORA_CAPTURE_DIR'];
      if (output != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('finance-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File(
            '$output/$tab.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
